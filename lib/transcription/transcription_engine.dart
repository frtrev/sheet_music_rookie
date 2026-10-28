import '../models/playback_instrument.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../audio/microphone_service.dart';
import '../audio/phrase_analyzer.dart';
import '../models/phrase_draft.dart';
import '../audio/note_segmenter.dart';
import '../audio/pitch_detector.dart';
import '../audio/pitch_smoother.dart';
import '../models/composition.dart';
import '../models/measure.dart';
import '../models/musical_note.dart';
import '../models/note_lyric.dart';
import '../models/pitch_detection_result.dart';
import '../models/raw_note_event.dart';
import '../models/voice_detection_settings.dart';
import '../services/settings_service.dart';
import 'measure_builder.dart';
import 'rhythm_quantizer.dart';

class _ScoreSnapshot {
  _ScoreSnapshot(this.composition, List<RawNoteEvent> events, this.cursor)
    : events = List.unmodifiable(events);
  final Composition composition;
  final List<RawNoteEvent> events;
  final int cursor;
}

class TranscriptionEngine {
  TranscriptionEngine({
    required ClefType clef,
    required OctaveRange octaveRange,
    Composition? initialComposition,
    List<RawNoteEvent> initialEvents = const [],
    MicrophoneService? microphone,
    SettingsService? settingsService,
  }) : _microphone = microphone ?? MicrophoneService(),
       _settingsService = settingsService ?? SettingsService(),
       rawEvents = [...initialEvents],
       composition = ValueNotifier(
         initialComposition ??
             Composition(clef: clef, octaveRange: octaveRange),
       ) {
    _savedSnapshot = _snapshot();
  }

  final ValueNotifier<PhraseDraft?> phraseDraft = ValueNotifier(null);
  final List<AudioFrame> _phraseFrames = [];
  final List<PitchTracePoint> _phraseTrace = [];
  int? _phraseOrigin;
  int? _phraseSilenceStart;
  int _phraseStartTick = 0;
  int _phraseGeneration = 0;
  int _lastTraceTimestamp = 0;
  bool _disposed = false;
  bool get _phraseMode =>
      settings.value.recordingAnalysisMode == RecordingAnalysisMode.phrase;

  void discardPhrase() {
    _phraseGeneration++;
    _phraseFrames.clear();
    _phraseTrace.clear();
    _phraseOrigin = null;
    _phraseSilenceStart = null;
    if (!_disposed) phraseDraft.value = null;
  }

  bool acceptPhrase() {
    final draft = phraseDraft.value;
    if (draft == null ||
        draft.stage != PhraseStage.review ||
        draft.events.isEmpty) {
      return false;
    }
    discardPhrase();
    _edit(() => _overwriteFromTick(draft.startTick, draft.events));
    return true;
  }

  Composition? _traceBase;
  Composition? _tracePreview;
  Composition _traceComposition(int endTick) {
    final score = composition.value;
    if (identical(_traceBase, score) &&
        _tracePreview != null &&
        _tracePreview!.editableEndTick > endTick) {
      return _tracePreview!;
    }
    _traceBase = score;
    final measures = [...score.measures];
    var capacity = score.editableEndTick;
    if (measures.isEmpty) {
      measures.add(const Measure(index: 0, notes: []));
    }
    while (capacity <= endTick) {
      final index = measures.length;
      measures.add(
        Measure(
          index: index,
          notes: const [],
          beatsPerMeasure: measures.last.effectiveBeats(score.beatsPerMeasure),
          beatUnit: measures.last.effectiveBeatUnit(score.beatUnit),
        ),
      );
      capacity += score.measureCapacityTicks(index - 1);
    }
    return _tracePreview = score.copyWith(measures: measures);
  }

  void _capturePhraseFrame(AudioFrame frame, PitchDetectionResult? pitch) {
    final stage = phraseDraft.value?.stage;
    if (stage != null && stage != PhraseStage.recording) return;
    var sum = 0.0;
    for (final sample in frame.samples) {
      sum += sample * sample;
    }
    final rms = math.sqrt(sum / frame.samples.length);
    final audible = rms > math.pow(10, settings.value.silenceThresholdDb / 20);
    if (_phraseOrigin == null) {
      if (!audible) return;
      _phraseOrigin = frame.timestampMs;
      _phraseStartTick = notationCursorTick.value.clamp(
        0,
        _totalTicks(rawEvents),
      );
      _lastTraceTimestamp = frame.timestampMs - 100;
    }
    _phraseFrames.add(frame);
    if (audible) {
      _phraseSilenceStart = null;
    } else {
      _phraseSilenceStart ??= frame.timestampMs;
    }
    final elapsed = frame.timestampMs - _phraseOrigin!;
    if (frame.timestampMs - _lastTraceTimestamp >= 65) {
      _lastTraceTimestamp = frame.timestampMs;
      final midi =
          pitch != null &&
              pitch.confidence >= settings.value.minimumConfidence &&
              audible
          ? 69 + 12 * math.log(pitch.frequencyHz / 440) / math.ln2
          : null;
      _phraseTrace.add(
        PitchTracePoint(
          _phraseStartTick +
              (elapsed * composition.value.tempoBpm * 480 / 60000).round(),
          midi,
        ),
      );
      phraseDraft.value = PhraseDraft(
        stage: PhraseStage.recording,
        startTick: _phraseStartTick,
        trace: List.unmodifiable(_phraseTrace),
        preview: _traceComposition(_phraseTrace.last.tick),
      );
    }
    if ((_phraseSilenceStart != null &&
            frame.timestampMs - _phraseSilenceStart! >=
                settings.value.phraseSilenceMs) ||
        elapsed >= 30000) {
      unawaited(finishPhrase());
    }
  }

  Future<void> finishPhrase() async {
    if (_phraseFrames.isEmpty ||
        phraseDraft.value?.stage != PhraseStage.recording) {
      return;
    }
    final generation = ++_phraseGeneration;
    final start = _phraseStartTick;
    final trace = List<PitchTracePoint>.unmodifiable(_phraseTrace);
    final request = PhraseAnalysisRequest(
      List.of(_phraseFrames),
      settings.value,
      composition.value.tempoBpm,
    );
    _phraseFrames.clear();
    _phraseOrigin = null;
    _phraseSilenceStart = null;
    phraseDraft.value = PhraseDraft(
      stage: PhraseStage.analyzing,
      startTick: start,
      trace: trace,
      preview: _traceComposition(trace.isEmpty ? start : trace.last.tick),
    );
    try {
      final events = await compute(analyzePhrase, request);
      if (_disposed || generation != _phraseGeneration) return;
      if (events.isEmpty) {
        phraseDraft.value = PhraseDraft(
          stage: PhraseStage.failed,
          startTick: start,
          trace: trace,
          message: 'No clear notes found. Try again or adjust the detection settings.',
        );
        return;
      }
      final previewEvents = _spliceEvents(rawEvents, start, events);
      final preview = composition.value.copyWith(
        measures: _measureBuilder.build(
          previewEvents,
          composition.value.tempoBpm,
          composition.value.beatsPerMeasure,
          beatUnit: composition.value.beatUnit,
          octaveTranspositionSemitones: composition.value.octaveRange.semitones,
          keySignature: composition.value.keySignature,
          measureTemplates: composition.value.measures,
        ),
      );
      phraseDraft.value = PhraseDraft(
        stage: PhraseStage.review,
        startTick: start,
        endTick: start + _totalTicks(events),
        events: List.unmodifiable(events),
        preview: preview,
        trace: trace,
      );
    } catch (_) {
      if (!_disposed && generation == _phraseGeneration) {
        phraseDraft.value = PhraseDraft(
          stage: PhraseStage.failed,
          startTick: start,
          trace: trace,
          message: 'Could not analyze this phrase. Discard it and try again.',
        );
      }
    }
  }

  final MicrophoneService _microphone;
  final SettingsService _settingsService;
  final PitchDetector _detector = const PitchDetector();
  final PitchSmoother _smoother = PitchSmoother();
  final NoteSegmenter _segmenter = NoteSegmenter();
  final MeasureBuilder _measureBuilder = const MeasureBuilder();
  final RhythmQuantizer _quantizer = const RhythmQuantizer();
  final List<RawNoteEvent> rawEvents;
  StreamSubscription<AudioFrame>? _subscription;
  int _lastRenderedActiveTicks = 0;
  bool _processing = false;
  List<RawNoteEvent>? _punchInBase;
  final List<RawNoteEvent> _punchInEvents = [];
  int _punchInStartTick = 0;
  bool _captureEnabled = true;

  final ValueNotifier<MicrophoneStatus> microphoneStatus = ValueNotifier(
    MicrophoneStatus.paused,
  );
  final ValueNotifier<PitchDetectionResult?> livePitch = ValueNotifier(null);
  final ValueNotifier<AudioFrame?> latestAudioFrame = ValueNotifier(null);
  final ValueNotifier<int> currentNoteDurationMs = ValueNotifier(0);
  final ValueNotifier<VoiceDetectionSettings> settings = ValueNotifier(
    const VoiceDetectionSettings(),
  );
  final ValueNotifier<int> notationCursorTick = ValueNotifier(0);
  final ValueNotifier<Composition> composition;

  late _ScoreSnapshot _savedSnapshot;

  _ScoreSnapshot _dirtySnapshot(_ScoreSnapshot snapshot) {
    final score = snapshot.composition;
    final measures = [...score.measures];
    // Live transcription can add an empty trailing bar without changing music.
    while (measures.length > 1 &&
        measures.last.notes.isEmpty &&
        measures.last.barlines.isEmpty &&
        measures.last.effectiveBeats(score.beatsPerMeasure) ==
            score.beatsPerMeasure &&
        measures.last.effectiveBeatUnit(score.beatUnit) == score.beatUnit) {
      measures.removeLast();
    }
    return _ScoreSnapshot(
      score.copyWith(measures: measures),
      snapshot.events,
      snapshot.cursor,
    );
  }

  bool get hasUnsavedChanges =>
      phraseDraft.value != null ||
      _recordingBefore != null ||
      !_sameContent(
        _dirtySnapshot(_savedSnapshot),
        _dirtySnapshot(_snapshot()),
      );

  void markSaved(Composition savedComposition, List<RawNoteEvent> savedEvents) {
    _savedSnapshot = _ScoreSnapshot(
      savedComposition,
      savedEvents,
      notationCursorTick.value,
    );
  }

  static const historyLimit = 100;
  final _undo = <_ScoreSnapshot>[];
  final _redo = <_ScoreSnapshot>[];
  _ScoreSnapshot? _recordingBefore;
  _ScoreSnapshot? _punchInBefore;
  final ValueNotifier<int> historyRevision = ValueNotifier(0);
  bool get canUndo => _undo.isNotEmpty || _recordingBefore != null;
  bool get canRedo => _redo.isNotEmpty && _recordingBefore == null;

  _ScoreSnapshot _snapshot() =>
      _ScoreSnapshot(composition.value, rawEvents, notationCursorTick.value);

  bool _sameContent(_ScoreSnapshot a, _ScoreSnapshot b) {
    bool lyricsEqual(List<NoteLyric> x, List<NoteLyric> y) =>
        listEquals(x.map((l) => l.xml).toList(), y.map((l) => l.xml).toList());
    if (a.events.length != b.events.length) return false;
    for (var i = 0; i < a.events.length; i++) {
      final x = a.events[i];
      final y = b.events[i];
      if (x.startTimeMs != y.startTimeMs ||
          x.endTimeMs != y.endTimeMs ||
          x.midiPitch != y.midiPitch ||
          x.frequencyHz != y.frequencyHz ||
          x.confidence != y.confidence ||
          x.accidental != y.accidental ||
          x.isRest != y.isRest ||
          x.tieToNext != y.tieToNext ||
          !lyricsEqual(x.lyrics, y.lyrics)) {
        return false;
      }
    }
    final x = a.composition;
    final y = b.composition;
    if (x.title != y.title ||
        x.keySignature != y.keySignature ||
        x.octaveRange != y.octaveRange ||
        x.beatsPerMeasure != y.beatsPerMeasure ||
        x.beatUnit != y.beatUnit ||
        x.tempoBpm != y.tempoBpm ||
        x.playbackInstrument != y.playbackInstrument ||
        x.measures.length != y.measures.length) {
      return false;
    }
    for (var i = 0; i < x.measures.length; i++) {
      final m = x.measures[i];
      final n = y.measures[i];
      if (m.beatsPerMeasure != n.beatsPerMeasure ||
          m.beatUnit != n.beatUnit ||
          !listEquals(m.barlines, n.barlines) ||
          m.notes.length != n.notes.length) {
        return false;
      }
      for (var j = 0; j < m.notes.length; j++) {
        final p = m.notes[j];
        final q = n.notes[j];
        if (p.midiPitch != q.midiPitch ||
            p.startTick != q.startTick ||
            p.durationTicks != q.durationTicks ||
            p.accidental != q.accidental ||
            p.flatSpelling != q.flatSpelling ||
            p.isRest != q.isRest ||
            p.tieFromPrevious != q.tieFromPrevious ||
            p.tieToNext != q.tieToNext ||
            !lyricsEqual(p.lyrics, q.lyrics)) {
          return false;
        }
      }
    }
    return true;
  }

  void _remember(_ScoreSnapshot before) {
    _undo.add(before);
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    historyRevision.value++;
  }

  T _edit<T>(T Function() action) {
    if (phraseDraft.value != null) discardPhrase();
    if (isPunchingIn) _finishPunchIn();
    final before = _snapshot();
    final result = action();
    if (!_sameContent(before, _snapshot())) _remember(before);
    return result;
  }

  void _beginRecordingChange() {
    if (_recordingBefore != null) return;
    _recordingBefore = _punchInBefore ?? _snapshot();
    historyRevision.value++;
  }

  void _restore(_ScoreSnapshot snapshot) {
    discardPhrase();
    final current = composition.value;
    _segmenter.reset();
    _smoother.clear();
    _lastRenderedActiveTicks = 0;
    _punchInBase = null;
    _punchInEvents.clear();
    _recordingBefore = null;
    _punchInBefore = null;
    currentNoteDurationMs.value = 0;
    rawEvents
      ..clear()
      ..addAll(snapshot.events);
    notationCursorTick.value = snapshot.cursor;
    composition.value = snapshot.composition.copyWith(
      microphoneActive: current.microphoneActive,
      metronomeMode: current.metronomeMode,
      playbackVolume: current.playbackVolume,
      metronomeVolume: current.metronomeVolume,
    );
    historyRevision.value++;
  }

  void _finishForHistory() {
    final event = _segmenter.finish(
      livePitch.value?.timestampMs ?? 0,
      settings.value,
    );
    if (event != null && _captureEnabled) _commitFinalized(event);
    if (isPunchingIn) _finishPunchIn();
    if (_recordingBefore != null) {
      _recordingBefore = null;
      _rebuildComposition();
      historyRevision.value++;
    }
  }

  bool undo() {
    _finishForHistory();
    if (_undo.isEmpty) return false;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
    return true;
  }

  bool redo() {
    _finishForHistory();
    if (_redo.isEmpty) return false;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
    return true;
  }

  void overwriteFromTick(int tick, List<RawNoteEvent> events) =>
      _edit(() => _overwriteFromTick(tick, events));
  bool? toggleTieAtTick(int tick) => _edit(() => _toggleTieAtTick(tick));
  bool removeNoteAtTick(int tick) => _edit(() => _removeNoteAtTick(tick));
  int insertMeasureAfterTick(int tick) =>
      _edit(() => _insertMeasureAfterTick(tick));
  void setMeasureTimeSignatureAtTick(
    int tick, {
    required int beatsPerMeasure,
    required int beatUnit,
  }) => _edit(
    () => _setMeasureTimeSignatureAtTick(
      tick,
      beatsPerMeasure: beatsPerMeasure,
      beatUnit: beatUnit,
    ),
  );
  ({int midiPitch, int durationTicks, bool isRest})? toggleRestAtTick(
    int tick,
  ) => _edit(() => _toggleRestAtTick(tick));
  ({int midiPitch, int durationTicks, bool isRest})? toggleNoteAtTick(
    int tick,
  ) => _edit(() {
    if (eventIndexAtTick(tick) != null) return _toggleRestAtTick(tick);
    final inserted = _toggleRestAtTick(tick);
    if (inserted == null) return null;
    return _toggleRestAtTick(notationCursorTick.value);
  });
  ({int midiPitch, int durationTicks, bool isRest})? writeNoteAtTick(
    int tick,
  ) => _edit(() {
    final index = eventIndexAtTick(tick);
    if (index != null && !rawEvents[index].isRest) {
      var position = _totalTicks(rawEvents.sublist(0, index));
      final fragment = _notationFragments(index).firstWhere((note) {
        final contains = tick < position + note.durationTicks;
        position += note.durationTicks;
        return contains;
      });
      return (
        midiPitch: rawEvents[index].midiPitch,
        durationTicks: fragment.durationTicks,
        isRest: false,
      );
    }
    if (index != null) return _toggleRestAtTick(tick);
    final inserted = _toggleRestAtTick(tick);
    if (inserted == null) return null;
    return _toggleRestAtTick(notationCursorTick.value);
  });

  ({int midiPitch, int durationTicks, bool isRest})? writeRestAtTick(
    int tick,
  ) => _edit(() {
    final index = eventIndexAtTick(tick);
    if (index != null && rawEvents[index].isRest) {
      return (
        midiPitch: 0,
        durationTicks: _ticksFor(rawEvents[index]),
        isRest: true,
      );
    }
    return _toggleRestAtTick(tick);
  });

  ({int midiPitch, int durationTicks})? editNoteAtTick(
    int tick, {
    int pitchDelta = 0,
    int durationDelta = 0,
  }) => _edit(
    () => _editNoteAtTick(
      tick,
      pitchDelta: pitchDelta,
      durationDelta: durationDelta,
    ),
  );
  void setPlaybackInstrument(PlaybackInstrument value) => _edit(() {
    composition.value = composition.value.copyWith(playbackInstrument: value);
  });

  void setTempoBpm(int value) => _edit(() {
    final next = value.clamp(20, 400);
    final previous = composition.value.tempoBpm;
    if (next == previous) return;
    final pieces = [
      for (final event in rawEvents) (event: event, ticks: _ticksFor(event)),
    ];
    composition.value = composition.value.copyWith(tempoBpm: next);
    _replaceWithPieces(pieces);
    _rebuildComposition();
  });

  void setKeySignature(KeySignature value) =>
      _edit(() => _setKeySignature(value));
  void setOctaveRange(OctaveRange value) => _edit(() => _setOctaveRange(value));
  void setTitle(String title) => _edit(() => _setTitle(title));
  void clear() => _edit(_clear);

  bool get isPunchingIn => _punchInBase != null;
  bool get captureEnabled => _captureEnabled;

  void setCaptureEnabled(bool enabled) {
    if (_captureEnabled == enabled) return;
    if (!enabled && _phraseMode) unawaited(finishPhrase());
    _captureEnabled = enabled;
    _segmenter.reset();
    _smoother.clear();
    _lastRenderedActiveTicks = 0;
    currentNoteDurationMs.value = 0;
    if (!enabled && isPunchingIn) _finishPunchIn();
    if (!_phraseMode) _rebuildComposition();
  }

  Future<void> initialize({bool autoStart = false}) async {
    settings.value = await _settingsService.load();
    if (autoStart) await startListening();
  }

  Future<void> startListening() async {
    microphoneStatus.value = MicrophoneStatus.starting;
    try {
      final granted = await _microphone.start();
      if (!granted) {
        microphoneStatus.value = MicrophoneStatus.unavailable;
        return;
      }
      await _subscription?.cancel();
      _subscription = _microphone.frames.listen(_processFrame);
      composition.value = composition.value.copyWith(microphoneActive: true);
      microphoneStatus.value = MicrophoneStatus.listening;
    } catch (_) {
      microphoneStatus.value = MicrophoneStatus.unavailable;
    }
  }

  Future<void> pauseListening() async {
    if (_phraseMode) await finishPhrase();
    if (!_phraseMode) {
      final completed = _segmenter.finish(
        livePitch.value?.timestampMs ?? 0,
        settings.value,
      );
      if (completed != null && _captureEnabled) {
        _commitFinalized(completed, endPunchIn: isPunchingIn);
      } else if (_captureEnabled && isPunchingIn) {
        _finishPunchIn();
      }
      _rebuildComposition();
    }
    await _subscription?.cancel();
    _subscription = null;
    await _microphone.stop();
    composition.value = composition.value.copyWith(microphoneActive: false);
    microphoneStatus.value = MicrophoneStatus.paused;
    currentNoteDurationMs.value = 0;
    _recordingBefore = null;
    _punchInBefore = null;
    historyRevision.value++;
  }

  void _processFrame(AudioFrame frame) {
    if (_processing) return;
    _processing = true;
    try {
      final detected = _detector.analyze(
        frame.samples,
        frame.timestampMs,
        settings.value,
      );
      final smoothed = detected == null
          ? null
          : _smoother.add(detected, settings.value.smoothingWindow);
      if (smoothed != null) livePitch.value = smoothed;
      final isVoice =
          smoothed != null &&
          smoothed.dbfs >= settings.value.silenceThresholdDb &&
          smoothed.confidence >= settings.value.minimumConfidence;
      microphoneStatus.value = isVoice
          ? MicrophoneStatus.voiceDetected
          : MicrophoneStatus.silence;
      if (_phraseMode) {
        if (_captureEnabled) _capturePhraseFrame(frame, detected);
        latestAudioFrame.value = frame;
        return;
      }
      final update = _segmenter.process(
        smoothed,
        frame.timestampMs,
        settings.value,
      );
      if (_captureEnabled &&
          (update.active != null || update.finalized != null)) {
        _beginRecordingChange();
      }
      final punchInEnded =
          _captureEnabled &&
          update.finalized != null &&
          isPunchingIn &&
          !isVoice;
      if (_captureEnabled && update.finalized != null) {
        _commitFinalized(update.finalized!, endPunchIn: punchInEnded);
        if (!isPunchingIn && update.active != null) {
          _rebuildComposition();
          _beginRecordingChange();
        }
      }
      currentNoteDurationMs.value = update.active?.durationMs ?? 0;
      final activeTicks = update.active == null
          ? 0
          : _quantizer.quantizeDuration(
              update.active!.durationMs,
              composition.value.tempoBpm,
            );
      if (_captureEnabled &&
          (update.finalized != null ||
              activeTicks != _lastRenderedActiveTicks)) {
        _lastRenderedActiveTicks = activeTicks;
        _rebuildComposition(active: update.active);
      }
      if (punchInEnded) {
        // A pause in the voice completes the current overwrite, but it should
        // not turn recording off. Keep a fresh punch-in anchored at the new
        // cursor so the next sung note behaves like recording a new sheet.
        beginPunchInAt(notationCursorTick.value);
      }
      latestAudioFrame.value = frame;
    } finally {
      _processing = false;
    }
  }

  void _rebuildComposition({RawNoteEvent? active}) {
    final preview = active == null
        ? _punchInEvents
        : [..._punchInEvents, active];
    final events = isPunchingIn
        ? preview.isEmpty
              ? _punchInBase!
              : _spliceEvents(_punchInBase!, _punchInStartTick, preview)
        : [...rawEvents, ?active];
    composition.value = composition.value.copyWith(
      measures: _measureBuilder.build(
        events,
        composition.value.tempoBpm,
        composition.value.beatsPerMeasure,
        beatUnit: composition.value.beatUnit,
        octaveTranspositionSemitones: composition.value.octaveRange.semitones,
        keySignature: composition.value.keySignature,
        measureTemplates: composition.value.measures,
      ),
    );
    if (active != null || preview.isNotEmpty) {
      notationCursorTick.value = isPunchingIn
          ? _punchInStartTick + _totalTicks(preview)
          : _totalTicks(events);
    }
  }

  void beginPunchInAt(int tick) {
    if (_phraseMode) {
      if (phraseDraft.value != null) return;
      notationCursorTick.value = tick.clamp(0, _totalTicks(rawEvents));
      return;
    }
    // Moving the cursor while recording commits any completed notes from the
    // previous punch-in. The active, unfinished sound is intentionally reset
    // so it cannot leak into the newly selected note.
    if (isPunchingIn) _finishPunchIn();
    _segmenter.reset();
    _smoother.clear();
    _lastRenderedActiveTicks = 0;
    currentNoteDurationMs.value = 0;
    _punchInBefore = _snapshot();
    _punchInBase = [...rawEvents];
    _punchInEvents.clear();
    _punchInStartTick = _eventStartAtTick(tick);
    notationCursorTick.value = _punchInStartTick;
    _rebuildComposition();
  }

  void _overwriteFromTick(int tick, List<RawNoteEvent> events) {
    final startTick = tick.clamp(0, _totalTicks(rawEvents)).toInt();
    final updated = _spliceEvents(rawEvents, startTick, events);
    rawEvents
      ..clear()
      ..addAll(updated);
    notationCursorTick.value = startTick + _totalTicks(events);
    _rebuildComposition();
  }

  void insertManualNote(int tick, int writtenMidiPitch, NoteValue value) {
    final soundingMidi =
        (writtenMidiPitch + composition.value.octaveRange.semitones)
            .clamp(0, 127)
            .toInt();
    final frequency = 440 * math.pow(2, (soundingMidi - 69) / 12);
    overwriteFromTick(tick, [
      RawNoteEvent(
        startTimeMs: 0,
        endTimeMs: _millisecondsForTicks(value.ticks),
        frequencyHz: frequency.toDouble(),
        midiPitch: soundingMidi,
        confidence: 1,
      ),
    ]);
  }

  int? eventIndexAtTick(int tick) {
    var position = 0;
    for (var index = 0; index < rawEvents.length; index++) {
      final end = position + _ticksFor(rawEvents[index]);
      if (tick >= position && tick < end) return index;
      position = end;
    }
    return null;
  }

  bool isRestAtTick(int tick) {
    final index = eventIndexAtTick(tick);
    return index != null && rawEvents[index].isRest;
  }

  Composition? _fragmentScore;
  int _fragmentEventCount = -1;
  final Map<int, List<MusicalNote>> _fragmentsBySource = {};

  List<MusicalNote> _notationFragments(int index) {
    if (!identical(_fragmentScore, composition.value) ||
        _fragmentEventCount != rawEvents.length) {
      _fragmentScore = composition.value;
      _fragmentEventCount = rawEvents.length;
      _fragmentsBySource.clear();
      final measures = _measureBuilder.build(
        rawEvents,
        composition.value.tempoBpm,
        composition.value.beatsPerMeasure,
        beatUnit: composition.value.beatUnit,
        measureTemplates: composition.value.measures,
      );
      for (final note in measures.expand((measure) => measure.notes)) {
        (_fragmentsBySource[note.sourceEventIndex] ??= []).add(note);
      }
    }
    return _fragmentsBySource[index] ?? const [];
  }

  // Materialize the displayed fragments only when an edit needs independent
  // events. This remains inside the edit's undo snapshot.
  void _splitSelectedEvent(int tick) {
    final index = eventIndexAtTick(tick);
    if (index == null) return;
    final fragments = _notationFragments(index);
    if (fragments.length < 2) return;
    final original = rawEvents[index];
    final pieces = <({RawNoteEvent event, int ticks})>[];
    for (final (i, event) in rawEvents.indexed) {
      if (i != index) {
        pieces.add((event: event, ticks: _ticksFor(event)));
        continue;
      }
      for (final (part, fragment) in fragments.indexed) {
        pieces.add((
          event: original.copyWith(
            lyrics: part == 0 ? original.lyrics : const [],
            accidental: part == 0 ? original.accidental : NoteAccidental.none,
            tieToNext:
                !original.isRest &&
                (part + 1 < fragments.length || original.tieToNext),
          ),
          ticks: fragment.durationTicks,
        ));
      }
    }
    _replaceWithPieces(pieces);
    _rebuildComposition();
  }

  void _detachIncomingTie(int index) {
    if (index > 0 && rawEvents[index - 1].tieToNext) {
      rawEvents[index - 1] = rawEvents[index - 1].copyWith(tieToNext: false);
    }
  }

  bool canToggleTieAtTick(int tick) {
    final index = eventIndexAtTick(tick);
    if (index == null || rawEvents[index].isRest) return false;
    var position = _totalTicks(rawEvents.sublist(0, index));
    final fragments = _notationFragments(index);
    for (final (i, fragment) in fragments.indexed) {
      if (tick < position + fragment.durationTicks) {
        return i + 1 < fragments.length ||
            (index + 1 < rawEvents.length && !rawEvents[index + 1].isRest);
      }
      position += fragment.durationTicks;
    }
    return false;
  }

  bool isTiedAtTick(int tick) {
    final index = eventIndexAtTick(tick);
    if (index == null) return false;
    var position = _totalTicks(rawEvents.sublist(0, index));
    for (final fragment in _notationFragments(index)) {
      if (tick < position + fragment.durationTicks) return fragment.tieToNext;
      position += fragment.durationTicks;
    }
    return false;
  }

  bool? _toggleTieAtTick(int tick) {
    _splitSelectedEvent(tick);
    final index = eventIndexAtTick(tick);
    if (index == null) return null;
    final original = rawEvents[index];
    if (original.tieToNext) {
      rawEvents[index] = original.copyWith(tieToNext: false);
      _rebuildComposition();
      return false;
    }
    if (!canToggleTieAtTick(tick)) return null;
    _splitSelectedEvent(_totalTicks(rawEvents.sublist(0, index + 1)));
    rawEvents[index] = original.copyWith(tieToNext: true);
    final source = rawEvents[index];
    final next = rawEvents[index + 1];
    rawEvents[index + 1] = next.copyWith(
      midiPitch: source.midiPitch,
      frequencyHz: source.frequencyHz,
      accidental: NoteAccidental.none,
      tieToNext: next.midiPitch == source.midiPitch && next.tieToNext,
    );
    _rebuildComposition();
    return true;
  }

  bool _removeNoteAtTick(int tick) {
    if (isPunchingIn) _finishPunchIn();
    final index = eventIndexAtTick(tick);
    if (index == null) return false;
    _splitSelectedEvent(tick);
    final groupStart = eventIndexAtTick(tick)!;
    final groupEnd = groupStart;
    _detachIncomingTie(groupStart);
    final startTick = _totalTicks(rawEvents.sublist(0, groupStart));
    rawEvents.removeRange(groupStart, groupEnd + 1);
    notationCursorTick.value = startTick.clamp(0, _totalTicks(rawEvents));
    _rebuildComposition();
    return true;
  }

  /// Inserts one complete silent measure after the measure containing [tick].
  /// The cursor's exact position is intentionally ignored so notes are never
  /// split except at the measure boundary itself.
  int _insertMeasureAfterTick(int tick) {
    if (isPunchingIn) _finishPunchIn();
    final current = composition.value;
    final totalTicks = _totalTicks(rawEvents);
    final editableEnd = current.editableEndTick;
    final boundedTick = tick.clamp(0, editableEnd).toInt();
    var measureIndex = current.measureIndexAtTick(boundedTick);
    if (boundedTick > 0 &&
        boundedTick == current.measureStartTick(measureIndex) &&
        eventIndexAtTick(boundedTick) == null) {
      measureIndex = math.max(0, measureIndex - 1);
    }
    final insertionTick = current.measureStartTick(measureIndex + 1);
    final capacity = current.measureCapacityTicks(measureIndex);
    final splitTick = math.min(insertionTick, totalTicks);
    final before = <({RawNoteEvent event, int ticks})>[];
    final after = <({RawNoteEvent event, int ticks})>[];
    var position = 0;
    for (final event in rawEvents) {
      final eventTicks = _ticksFor(event);
      final end = position + eventTicks;
      if (end <= splitTick) {
        before.add((event: event, ticks: eventTicks));
      } else if (position >= splitTick) {
        after.add((event: event, ticks: eventTicks));
      } else {
        before.add((
          event: event.copyWith(tieToNext: false),
          ticks: splitTick - position,
        ));
        after.add((event: event, ticks: end - splitTick));
      }
      position = end;
    }
    if (before.isNotEmpty && before.last.event.tieToNext) {
      final last = before.removeLast();
      before.add((
        event: last.event.copyWith(tieToNext: false),
        ticks: last.ticks,
      ));
    }

    final silenceBeforeMeasure = insertionTick - splitTick;
    final pieces = <({RawNoteEvent event, int ticks})>[
      ...before,
      ..._restPieces(silenceBeforeMeasure),
      ..._restPieces(capacity),
      ...after,
    ];
    _replaceWithPieces(pieces);
    final sourceMeasure = current.measures[measureIndex];
    final templates = [...current.measures]
      ..insert(
        measureIndex + 1,
        Measure(
          index: measureIndex + 1,
          beatsPerMeasure: sourceMeasure.effectiveBeats(
            current.beatsPerMeasure,
          ),
          beatUnit: sourceMeasure.effectiveBeatUnit(current.beatUnit),
        ),
      );
    composition.value = current.copyWith(
      measures: [
        for (final (index, measure) in templates.indexed)
          Measure(
            index: index,
            notes: measure.notes,
            barlines: measure.barlines,
            beatsPerMeasure: measure.beatsPerMeasure,
            beatUnit: measure.beatUnit,
          ),
      ],
    );
    notationCursorTick.value = boundedTick;
    _rebuildComposition();
    return insertionTick;
  }

  void _setMeasureTimeSignatureAtTick(
    int tick, {
    required int beatsPerMeasure,
    required int beatUnit,
  }) {
    if (isPunchingIn) _finishPunchIn();
    final current = composition.value;
    if (current.measures.isEmpty) return;
    final measureIndex = current.measureIndexAtTick(tick);
    final templates = [
      for (final measure in current.measures)
        Measure(
          index: measure.index,
          notes: measure.notes,
          barlines: measure.barlines,
          beatsPerMeasure: measure.index == measureIndex
              ? beatsPerMeasure.clamp(1, 32)
              : measure.beatsPerMeasure,
          beatUnit: measure.index == measureIndex ? beatUnit : measure.beatUnit,
        ),
    ];
    composition.value = current.copyWith(measures: templates);
    _rebuildComposition();
    notationCursorTick.value = tick
        .clamp(0, composition.value.editableEndTick)
        .toInt();
  }

  List<({RawNoteEvent event, int ticks})> _restPieces(int ticks) {
    final pieces = <({RawNoteEvent event, int ticks})>[];
    var remaining = ticks;
    for (final value in NoteValue.values.reversed) {
      while (remaining >= value.ticks) {
        pieces.add((
          event: const RawNoteEvent(
            startTimeMs: 0,
            endTimeMs: 0,
            frequencyHz: 0,
            midiPitch: 0,
            confidence: 1,
            accidental: NoteAccidental.none,
            isRest: true,
          ),
          ticks: value.ticks,
        ));
        remaining -= value.ticks;
      }
    }
    assert(remaining == 0, 'Measure duration must align to the notation grid.');
    return pieces;
  }

  void _replaceWithPieces(List<({RawNoteEvent event, int ticks})> pieces) {
    var timestampMs = 0;
    rawEvents.clear();
    for (final piece in pieces) {
      final event = _eventWithTicks(piece.event, piece.ticks, timestampMs);
      rawEvents.add(event);
      timestampMs = event.endTimeMs;
    }
  }

  bool canToggleRestAtTick(int tick) {
    if (eventIndexAtTick(tick) != null) return true;
    final totalTicks = _totalTicks(rawEvents);
    final editableEnd = composition.value.editableEndTick;
    return tick >= totalTicks && tick < editableEnd;
  }

  ({int midiPitch, int durationTicks, bool isRest})? _toggleRestAtTick(
    int tick,
  ) {
    _splitSelectedEvent(tick);
    final eventIndex = eventIndexAtTick(tick);
    if (eventIndex != null) {
      final original = rawEvents[eventIndex];
      final durationTicks = _ticksFor(original);
      if (original.isRest) {
        final writtenFirstLine = composition.value.clef.bottomLineMidi;
        final soundingMidi =
            (writtenFirstLine + composition.value.octaveRange.semitones)
                .clamp(0, 127)
                .toInt();
        rawEvents[eventIndex] = RawNoteEvent(
          lyrics: original.lyrics,
          startTimeMs: original.startTimeMs,
          endTimeMs: original.endTimeMs,
          frequencyHz: (440 * math.pow(2, (soundingMidi - 69) / 12)).toDouble(),
          midiPitch: soundingMidi,
          confidence: 1,
        );
        _rebuildComposition();
        return (
          midiPitch: soundingMidi,
          durationTicks: durationTicks,
          isRest: false,
        );
      }
      rawEvents[eventIndex] = original.copyWith(
        accidental: NoteAccidental.none,
        isRest: true,
        tieToNext: false,
      );
      if (eventIndex > 0 && rawEvents[eventIndex - 1].tieToNext) {
        rawEvents[eventIndex - 1] = rawEvents[eventIndex - 1].copyWith(
          tieToNext: false,
        );
      }
      _rebuildComposition();
      return (
        midiPitch: original.midiPitch,
        durationTicks: durationTicks,
        isRest: true,
      );
    }

    if (!canToggleRestAtTick(tick)) return null;
    final totalTicks = _totalTicks(rawEvents);
    final score = composition.value;
    final measureIndex = score.measureIndexAtTick(tick);
    final measureStart = score.measureStartTick(measureIndex);
    final capacity = score.measureCapacityTicks(measureIndex);
    final unit = score.measures[measureIndex].effectiveBeatUnit(score.beatUnit);
    final beatTicks = 1920 ~/ unit;
    final localTick = tick - measureStart;
    // Exact halfway taps choose the earlier beat. Stay inside this measure
    // and never overwrite an existing note just to align a new rest.
    var beat = ((localTick + beatTicks ~/ 2 - 1) ~/ beatTicks).clamp(
      0,
      capacity ~/ beatTicks - 1,
    );
    var snappedTick = measureStart + beat * beatTicks;
    if (snappedTick < totalTicks) {
      beat = (totalTicks - measureStart + beatTicks - 1) ~/ beatTicks;
      snappedTick = measureStart + beat * beatTicks;
    }
    if (snappedTick + beatTicks > measureStart + capacity) return null;
    if (snappedTick > totalTicks) _appendRestDuration(snappedTick - totalTicks);
    _appendRestDuration(beatTicks);
    notationCursorTick.value = snappedTick;
    _rebuildComposition();
    return (midiPitch: 0, durationTicks: beatTicks, isRest: true);
  }

  void _appendRestDuration(int ticks) {
    var remaining = ticks;
    var startMs = rawEvents.fold<int>(
      0,
      (sum, event) => sum + event.durationMs,
    );
    for (final value in NoteValue.values.reversed) {
      while (remaining >= value.ticks) {
        final durationMs = _millisecondsForTicks(value.ticks);
        rawEvents.add(
          RawNoteEvent(
            startTimeMs: startMs,
            endTimeMs: startMs + durationMs,
            frequencyHz: 0,
            midiPitch: 0,
            confidence: 1,
            accidental: NoteAccidental.none,
            isRest: true,
          ),
        );
        startMs += durationMs;
        remaining -= value.ticks;
      }
    }
    assert(remaining == 0, 'Rest duration must align to the notation grid.');
  }

  ({int midiPitch, int durationTicks})? _editNoteAtTick(
    int tick, {
    int pitchDelta = 0,
    int durationDelta = 0,
  }) {
    final eventIndex = eventIndexAtTick(tick);
    if (eventIndex == null) return null;

    _splitSelectedEvent(tick);
    final selectedIndex = eventIndexAtTick(tick)!;
    final groupStart = selectedIndex;
    final groupEnd = selectedIndex;
    final original = rawEvents[selectedIndex];
    if (original.isRest && pitchDelta != 0) return null;
    final durationEventIndex = selectedIndex;
    final durationEvent = rawEvents[durationEventIndex];
    final originalTicks = _ticksFor(durationEvent);
    final originalValueIndex = NoteValue.values.indexWhere(
      (value) => value.ticks == originalTicks,
    );
    final nextValueIndex = (originalValueIndex + durationDelta)
        .clamp(0, NoteValue.values.length - 1)
        .toInt();
    final nextValue = NoteValue.values[nextValueIndex];
    final groupPitch = rawEvents[groupStart].midiPitch;
    final nextMidi = (groupPitch + pitchDelta).clamp(0, 127).toInt();
    final isBlackKey = const {1, 3, 6, 8, 10}.contains(nextMidi % 12);
    final writtenPitchClass =
        (nextMidi - composition.value.octaveRange.semitones) % 12;
    if (nextMidi == groupPitch && nextValue.ticks == originalTicks) {
      return (
        midiPitch: groupPitch,
        durationTicks: _totalTicks(rawEvents.sublist(groupStart, groupEnd + 1)),
      );
    }
    final accidental = pitchDelta == 0
        ? rawEvents[groupStart].accidental
        : isBlackKey
        ? (pitchDelta > 0 ? NoteAccidental.sharp : NoteAccidental.flat)
        : composition.value.keySignature.alterationForNaturalPitchClass(
                writtenPitchClass,
              ) !=
              0
        ? NoteAccidental.natural
        : NoteAccidental.automatic;
    final frequency = 440 * math.pow(2, (nextMidi - 69) / 12);

    if (pitchDelta != 0 || nextValue.ticks < originalTicks) {
      rawEvents[selectedIndex] = rawEvents[selectedIndex].copyWith(
        tieToNext: false,
      );
      if (pitchDelta != 0) _detachIncomingTie(selectedIndex);
    }
    for (var index = groupStart; index <= groupEnd; index++) {
      final event = rawEvents[index];
      final editedTicks = index == durationEventIndex
          ? nextValue.ticks
          : _ticksFor(event);
      rawEvents[index] = RawNoteEvent(
        lyrics: event.lyrics,
        startTimeMs: event.startTimeMs,
        endTimeMs: event.startTimeMs + _millisecondsForTicks(editedTicks),
        frequencyHz: frequency.toDouble(),
        midiPitch: nextMidi,
        confidence: event.confidence,
        accidental: index == groupStart ? accidental : NoteAccidental.none,
        isRest: event.isRest,
        tieToNext: event.tieToNext,
      );
    }
    if (nextValue.ticks != originalTicks) {
      final pieces = <({RawNoteEvent event, int ticks})>[];
      var consumeRestTicks = math.max(0, nextValue.ticks - originalTicks);
      for (final (index, event) in rawEvents.indexed) {
        var ticks = _ticksFor(event);
        if (index > groupEnd && consumeRestTicks > 0) {
          if (event.isRest) {
            final consumed = math.min(ticks, consumeRestTicks);
            ticks -= consumed;
            consumeRestTicks -= consumed;
          } else {
            consumeRestTicks = 0;
          }
        }
        if (ticks > 0) pieces.add((event: event, ticks: ticks));
        if (index == groupEnd && nextValue.ticks < originalTicks) {
          pieces.addAll(_restPieces(originalTicks - nextValue.ticks));
        }
      }
      _replaceWithPieces(pieces);
    }
    _rebuildComposition();
    final groupTicks = rawEvents
        .sublist(groupStart, groupEnd + 1)
        .fold<int>(0, (total, event) => total + _ticksFor(event));
    return (midiPitch: nextMidi, durationTicks: groupTicks);
  }

  void _commitFinalized(RawNoteEvent event, {bool endPunchIn = false}) {
    if (isPunchingIn) {
      _punchInEvents.add(event);
      if (endPunchIn) _finishPunchIn();
    } else {
      final before = _recordingBefore ?? _snapshot();
      rawEvents.add(event);
      _recordingBefore = null;
      _remember(before);
      notationCursorTick.value = _totalTicks(rawEvents);
    }
  }

  void _finishPunchIn() {
    final base = _punchInBase;
    if (base == null) return;
    if (_punchInEvents.isEmpty) {
      // Merely moving the recording cursor is not an edit. Splicing an empty
      // replacement inside a note would divide that note at every tap.
      _punchInBase = null;
      _punchInBefore = null;
      _recordingBefore = null;
      notationCursorTick.value = _punchInStartTick;
      return;
    }
    final before = _recordingBefore ?? _punchInBefore ?? _snapshot();
    final endTick = _punchInStartTick + _totalTicks(_punchInEvents);
    rawEvents
      ..clear()
      ..addAll(_spliceEvents(base, _punchInStartTick, _punchInEvents));
    _punchInBase = null;
    _punchInEvents.clear();
    notationCursorTick.value = endTick;
    _recordingBefore = null;
    _punchInBefore = null;
    _rebuildComposition();
    if (!_sameContent(before, _snapshot())) _remember(before);
  }

  int _eventStartAtTick(int requestedTick) {
    final total = _totalTicks(rawEvents);
    final tick = requestedTick.clamp(0, total).toInt();
    var position = 0;
    for (final event in rawEvents) {
      final end = position + _ticksFor(event);
      if (tick >= position && tick < end) return position;
      position = end;
    }
    return tick;
  }

  List<RawNoteEvent> _spliceEvents(
    List<RawNoteEvent> base,
    int requestedStartTick,
    List<RawNoteEvent> replacements,
  ) {
    final total = _totalTicks(base);
    final startTick = requestedStartTick.clamp(0, total).toInt();
    final endTick = startTick + _totalTicks(replacements);
    final pieces = <({RawNoteEvent event, int ticks})>[];
    var position = 0;

    for (final event in base) {
      final ticks = _ticksFor(event);
      final eventEnd = position + ticks;
      final prefixTicks =
          (eventEnd < startTick ? eventEnd : startTick) - position;
      if (prefixTicks > 0) pieces.add((event: event, ticks: prefixTicks));
      position = eventEnd;
      if (position >= startTick) break;
    }
    for (final event in replacements) {
      pieces.add((event: event, ticks: _ticksFor(event)));
    }

    position = 0;
    for (final event in base) {
      final ticks = _ticksFor(event);
      final eventEnd = position + ticks;
      if (eventEnd > endTick) {
        final suffixTicks =
            eventEnd - (position > endTick ? position : endTick);
        if (suffixTicks > 0) pieces.add((event: event, ticks: suffixTicks));
      }
      position = eventEnd;
    }

    var timestampMs = 0;
    final result = <RawNoteEvent>[];
    for (final piece in pieces) {
      final event = _eventWithTicks(piece.event, piece.ticks, timestampMs);
      result.add(event);
      timestampMs = event.endTimeMs;
    }
    return result;
  }

  int _ticksFor(RawNoteEvent event) =>
      _quantizer.quantizeDuration(event.durationMs, composition.value.tempoBpm);

  int _totalTicks(List<RawNoteEvent> events) =>
      events.fold(0, (sum, event) => sum + _ticksFor(event));

  int _millisecondsForTicks(int ticks) =>
      (ticks * 60000 / (composition.value.tempoBpm * 480)).round();

  RawNoteEvent _eventWithTicks(RawNoteEvent source, int ticks, int startMs) {
    final durationMs = _millisecondsForTicks(ticks);
    return RawNoteEvent(
      startTimeMs: startMs,
      endTimeMs: startMs + durationMs,
      lyrics: source.lyrics,
      frequencyHz: source.frequencyHz,
      midiPitch: source.midiPitch,
      confidence: source.confidence,
      accidental: source.accidental,
      isRest: source.isRest,
      tieToNext: source.tieToNext,
    );
  }

  Future<void> updateSettings(VoiceDetectionSettings value) async {
    if (value.recordingAnalysisMode != settings.value.recordingAnalysisMode) {
      discardPhrase();
      _segmenter.reset();
      _smoother.clear();
    }
    settings.value = value;
    await _settingsService.save(value);
  }

  void setMetronomeMode(MetronomeMode mode) {
    composition.value = composition.value.copyWith(metronomeMode: mode);
  }

  void setVolumes({
    required double playbackVolume,
    required double metronomeVolume,
  }) {
    composition.value = composition.value.copyWith(
      playbackVolume: playbackVolume.clamp(0.0, 1.0).toDouble(),
      metronomeVolume: metronomeVolume.clamp(0.0, 1.0).toDouble(),
    );
  }

  void _setKeySignature(KeySignature keySignature) {
    if (keySignature == composition.value.keySignature) return;
    composition.value = composition.value.copyWith(keySignature: keySignature);
    _rebuildComposition();
  }

  void _setOctaveRange(OctaveRange octaveRange) {
    final previous = composition.value.octaveRange;
    if (previous == octaveRange) return;
    if (isPunchingIn) _finishPunchIn();
    final pitchDelta = octaveRange.semitones - previous.semitones;
    for (var index = 0; index < rawEvents.length; index++) {
      final event = rawEvents[index];
      if (event.isRest) continue;
      final midiPitch = (event.midiPitch + pitchDelta).clamp(0, 127).toInt();
      rawEvents[index] = event.copyWith(
        midiPitch: midiPitch,
        frequencyHz: (440 * math.pow(2, (midiPitch - 69) / 12)).toDouble(),
      );
    }
    composition.value = composition.value.copyWith(octaveRange: octaveRange);
    _rebuildComposition();
  }

  void _setTitle(String title) {
    composition.value = composition.value.copyWith(title: title.trim());
  }

  void _clear() {
    rawEvents.clear();
    _segmenter.reset();
    _smoother.clear();
    _lastRenderedActiveTicks = 0;
    _punchInBase = null;
    _punchInEvents.clear();
    notationCursorTick.value = 0;
    currentNoteDurationMs.value = 0;
    _rebuildComposition();
  }

  Future<void> dispose() async {
    _disposed = true;
    discardPhrase();
    await _subscription?.cancel();
    await _microphone.dispose();
    microphoneStatus.dispose();
    livePitch.dispose();
    latestAudioFrame.dispose();
    currentNoteDurationMs.dispose();
    settings.dispose();
    notationCursorTick.dispose();
    composition.dispose();
    historyRevision.dispose();
    phraseDraft.dispose();
  }
}
