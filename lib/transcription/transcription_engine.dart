import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../audio/microphone_service.dart';
import '../audio/note_segmenter.dart';
import '../audio/pitch_detector.dart';
import '../audio/pitch_smoother.dart';
import '../models/composition.dart';
import '../models/musical_note.dart';
import '../models/pitch_detection_result.dart';
import '../models/raw_note_event.dart';
import '../models/voice_detection_settings.dart';
import '../services/settings_service.dart';
import 'measure_builder.dart';
import 'rhythm_quantizer.dart';

class TranscriptionEngine {
  TranscriptionEngine({
    required ClefType clef,
    required OctaveRange octaveRange,
    MicrophoneService? microphone,
    SettingsService? settingsService,
  }) : _microphone = microphone ?? MicrophoneService(),
       _settingsService = settingsService ?? SettingsService(),
       composition = ValueNotifier(
         Composition(clef: clef, octaveRange: octaveRange),
       );

  final MicrophoneService _microphone;
  final SettingsService _settingsService;
  final PitchDetector _detector = const PitchDetector();
  final PitchSmoother _smoother = PitchSmoother();
  final NoteSegmenter _segmenter = NoteSegmenter();
  final MeasureBuilder _measureBuilder = const MeasureBuilder();
  final RhythmQuantizer _quantizer = const RhythmQuantizer();
  final List<RawNoteEvent> rawEvents = [];
  StreamSubscription<AudioFrame>? _subscription;
  int _lastRenderedActiveTicks = 0;
  bool _processing = false;
  List<RawNoteEvent>? _punchInBase;
  final List<RawNoteEvent> _punchInEvents = [];
  int _punchInStartTick = 0;

  final ValueNotifier<MicrophoneStatus> microphoneStatus = ValueNotifier(
    MicrophoneStatus.starting,
  );
  final ValueNotifier<PitchDetectionResult?> livePitch = ValueNotifier(null);
  final ValueNotifier<int> currentNoteDurationMs = ValueNotifier(0);
  final ValueNotifier<VoiceDetectionSettings> settings = ValueNotifier(
    const VoiceDetectionSettings(),
  );
  final ValueNotifier<int> notationCursorTick = ValueNotifier(0);
  final ValueNotifier<Composition> composition;

  bool get isPunchingIn => _punchInBase != null;

  Future<void> initialize() async {
    settings.value = await _settingsService.load();
    await startListening();
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
    final completed = _segmenter.finish(
      livePitch.value?.timestampMs ?? 0,
      settings.value,
    );
    if (completed != null) {
      _commitFinalized(completed, endPunchIn: isPunchingIn);
    } else if (isPunchingIn) {
      _finishPunchIn();
    }
    _rebuildComposition();
    await _subscription?.cancel();
    _subscription = null;
    await _microphone.stop();
    composition.value = composition.value.copyWith(microphoneActive: false);
    microphoneStatus.value = MicrophoneStatus.paused;
    currentNoteDurationMs.value = 0;
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
      final update = _segmenter.process(
        smoothed,
        frame.timestampMs,
        settings.value,
      );
      final punchInEnded = update.finalized != null && isPunchingIn && !isVoice;
      if (update.finalized != null) {
        _commitFinalized(update.finalized!, endPunchIn: punchInEnded);
      }
      currentNoteDurationMs.value = update.active?.durationMs ?? 0;
      final activeTicks = update.active == null
          ? 0
          : _quantizer.quantizeDuration(
              update.active!.durationMs,
              composition.value.tempoBpm,
            );
      if (update.finalized != null || activeTicks != _lastRenderedActiveTicks) {
        _lastRenderedActiveTicks = activeTicks;
        _rebuildComposition(active: update.active);
      }
      if (punchInEnded) unawaited(_pauseAfterPunchIn());
    } finally {
      _processing = false;
    }
  }

  void _rebuildComposition({RawNoteEvent? active}) {
    final preview = active == null
        ? _punchInEvents
        : [..._punchInEvents, active];
    final events = isPunchingIn
        ? _spliceEvents(_punchInBase!, _punchInStartTick, preview)
        : [...rawEvents, ?active];
    composition.value = composition.value.copyWith(
      measures: _measureBuilder.build(
        events,
        composition.value.tempoBpm,
        composition.value.beatsPerMeasure,
        octaveTranspositionSemitones: composition.value.octaveRange.semitones,
        keySignature: composition.value.keySignature,
      ),
    );
    if (active != null || preview.isNotEmpty) {
      notationCursorTick.value = isPunchingIn
          ? _punchInStartTick + _totalTicks(preview)
          : _totalTicks(events);
    }
  }

  void beginPunchInAt(int tick) {
    _segmenter.reset();
    _smoother.clear();
    _lastRenderedActiveTicks = 0;
    currentNoteDurationMs.value = 0;
    _punchInBase = [...rawEvents];
    _punchInEvents.clear();
    _punchInStartTick = tick.clamp(0, _totalTicks(rawEvents)).toInt();
    notationCursorTick.value = _punchInStartTick;
    _rebuildComposition();
  }

  void overwriteFromTick(int tick, List<RawNoteEvent> events) {
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

  bool canToggleTieAtTick(int tick) {
    final index = eventIndexAtTick(tick);
    return index != null &&
        index + 1 < rawEvents.length &&
        !rawEvents[index].isRest &&
        !rawEvents[index + 1].isRest;
  }

  bool isTiedAtTick(int tick) {
    final index = eventIndexAtTick(tick);
    return index != null && rawEvents[index].tieToNext;
  }

  bool? toggleTieAtTick(int tick) {
    final index = eventIndexAtTick(tick);
    if (index == null) return null;
    final original = rawEvents[index];
    if (original.tieToNext) {
      rawEvents[index] = original.copyWith(tieToNext: false);
      _rebuildComposition();
      return false;
    }
    if (!canToggleTieAtTick(tick)) return null;
    rawEvents[index] = original.copyWith(tieToNext: true);
    _normalizeTiedGroupPitch(index);
    _rebuildComposition();
    return true;
  }

  void _normalizeTiedGroupPitch(int index) {
    final (start, end) = _tiedGroupBounds(index);
    final source = rawEvents[start];
    for (var current = start + 1; current <= end; current++) {
      rawEvents[current] = rawEvents[current].copyWith(
        midiPitch: source.midiPitch,
        frequencyHz: source.frequencyHz,
        accidental: NoteAccidental.none,
      );
    }
  }

  (int, int) _tiedGroupBounds(int index) {
    var start = index;
    while (start > 0 && rawEvents[start - 1].tieToNext) {
      start--;
    }
    var end = index;
    while (end + 1 < rawEvents.length && rawEvents[end].tieToNext) {
      end++;
    }
    return (start, end);
  }

  bool canToggleRestAtTick(int tick) {
    if (eventIndexAtTick(tick) != null) return true;
    final totalTicks = _totalTicks(rawEvents);
    final editableEnd =
        composition.value.measures.length *
        composition.value.beatsPerMeasure *
        480;
    return tick >= totalTicks && tick < editableEnd;
  }

  ({int midiPitch, int durationTicks, bool isRest})? toggleRestAtTick(
    int tick,
  ) {
    final eventIndex = eventIndexAtTick(tick);
    if (eventIndex != null) {
      final original = rawEvents[eventIndex];
      final durationTicks = _ticksFor(original);
      if (original.isRest) {
        final writtenFirstLine = composition.value.clef == ClefType.treble
            ? 64 // E4
            : 43; // G2
        final soundingMidi =
            (writtenFirstLine + composition.value.octaveRange.semitones)
                .clamp(0, 127)
                .toInt();
        rawEvents[eventIndex] = RawNoteEvent(
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
    if (tick > totalTicks) _appendRestDuration(tick - totalTicks);
    final capacity = composition.value.beatsPerMeasure * 480;
    final positionInMeasure = tick % capacity;
    final available = positionInMeasure == 0
        ? capacity
        : capacity - positionInMeasure;
    final value = NoteValue.values.reversed.firstWhere(
      (candidate) => candidate.ticks <= math.min(480, available),
    );
    _appendRestDuration(value.ticks);
    _rebuildComposition();
    return (midiPitch: 0, durationTicks: value.ticks, isRest: true);
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

  ({int midiPitch, int durationTicks})? editNoteAtTick(
    int tick, {
    int pitchDelta = 0,
    int durationDelta = 0,
  }) {
    final eventIndex = eventIndexAtTick(tick);
    if (eventIndex == null) return null;

    final (groupStart, groupEnd) = _tiedGroupBounds(eventIndex);
    final original = rawEvents[eventIndex];
    if (original.isRest && pitchDelta != 0) return null;
    final durationEventIndex = groupStart == groupEnd ? eventIndex : groupEnd;
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

    for (var index = groupStart; index <= groupEnd; index++) {
      final event = rawEvents[index];
      final editedTicks = index == durationEventIndex
          ? nextValue.ticks
          : _ticksFor(event);
      rawEvents[index] = RawNoteEvent(
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
      rawEvents.add(event);
      notationCursorTick.value = _totalTicks(rawEvents);
    }
  }

  void _finishPunchIn() {
    final base = _punchInBase;
    if (base == null) return;
    final endTick = _punchInStartTick + _totalTicks(_punchInEvents);
    rawEvents
      ..clear()
      ..addAll(_spliceEvents(base, _punchInStartTick, _punchInEvents));
    _punchInBase = null;
    _punchInEvents.clear();
    notationCursorTick.value = endTick;
  }

  Future<void> _pauseAfterPunchIn() async {
    await _subscription?.cancel();
    _subscription = null;
    await _microphone.stop();
    composition.value = composition.value.copyWith(microphoneActive: false);
    microphoneStatus.value = MicrophoneStatus.paused;
    currentNoteDurationMs.value = 0;
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
      frequencyHz: source.frequencyHz,
      midiPitch: source.midiPitch,
      confidence: source.confidence,
      accidental: source.accidental,
      isRest: source.isRest,
      tieToNext: source.tieToNext,
    );
  }

  Future<void> updateSettings(VoiceDetectionSettings value) async {
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

  void setKeySignature(KeySignature keySignature) {
    composition.value = composition.value.copyWith(keySignature: keySignature);
    _rebuildComposition();
  }

  void clear() {
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
    await _subscription?.cancel();
    await _microphone.dispose();
    microphoneStatus.dispose();
    livePitch.dispose();
    currentNoteDurationMs.dispose();
    settings.dispose();
    notationCursorTick.dispose();
    composition.dispose();
  }
}
