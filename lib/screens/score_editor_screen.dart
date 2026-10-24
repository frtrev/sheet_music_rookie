import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/microphone_service.dart';
import '../models/composition.dart';
import '../models/measure.dart';
import '../models/musical_note.dart';
import '../models/raw_note_event.dart';
import '../notation/rest_symbol.dart';
import '../notation/score_renderer.dart';
import '../services/composition_storage_service.dart';
import '../services/metronome_service.dart';
import '../services/practice_service.dart';
import '../services/screen_awake_service.dart';
import '../services/score_playback_service.dart';
import '../transcription/transcription_engine.dart';
import '../widgets/live_pitch_monitor.dart';
import '../widgets/practice_pitch_gauge.dart';
import '../widgets/voice_settings_panel.dart';

class ScoreEditorScreen extends StatefulWidget {
  const ScoreEditorScreen({
    super.key,
    required this.clef,
    required this.octaveRange,
    this.initialComposition,
    this.initialEvents = const [],
    this.savePath,
  });
  final ClefType clef;
  final OctaveRange octaveRange;
  final Composition? initialComposition;
  final List<RawNoteEvent> initialEvents;
  final String? savePath;

  @override
  State<ScoreEditorScreen> createState() => _ScoreEditorScreenState();
}

class _ScoreEditorScreenState extends State<ScoreEditorScreen>
    with WidgetsBindingObserver {
  late final TranscriptionEngine _engine;
  late final ScorePlaybackService _playback;
  late final ScorePlaybackService _notePreview;
  late final MetronomeService _metronome;
  final ScreenAwakeService _screenAwake = ScreenAwakeService();
  final CompositionStorageService _storage = CompositionStorageService();
  final ScrollController _scoreScroll = ScrollController();
  final ScrollController _pageScroll = ScrollController();
  bool _pausedByUser = true;
  bool _settingsExpanded = false;
  bool _resumeListeningAfterPlayback = false;
  bool _cursorScrollScheduled = false;
  bool _saving = false;
  bool _practiceActive = false;
  PracticeSession? _practiceSession;
  final ValueNotifier<double> _practiceProgress = ValueNotifier(0);
  String? _savePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = TranscriptionEngine(
      clef: widget.clef,
      octaveRange: widget.octaveRange,
      initialComposition: widget.initialComposition,
      initialEvents: widget.initialEvents,
    );
    _savePath = widget.savePath;
    _playback = ScorePlaybackService()..onComplete = _playbackCompleted;
    _notePreview = ScorePlaybackService();
    _metronome = MetronomeService();
    _playback.position.addListener(_playbackPositionChanged);
    _playback.isPlaying.addListener(_transportWakeStateChanged);
    _engine.composition.addListener(_compositionChanged);
    _engine.notationCursorTick.addListener(_notationCursorChanged);
    _engine.microphoneStatus.addListener(_microphoneStatusChanged);
    _engine.livePitch.addListener(_practicePitchChanged);
    unawaited(_engine.initialize());
  }

  void _microphoneStatusChanged() {
    final status = _engine.microphoneStatus.value;
    if (_practiceActive && status != MicrophoneStatus.voiceDetected) {
      _practiceSession?.process(null, voiceDetected: false);
      _practiceProgress.value = 0;
    }
    if (status == MicrophoneStatus.paused ||
        status == MicrophoneStatus.unavailable) {
      unawaited(_metronome.stop());
    }
    _syncScreenAwake();
  }

  void _transportWakeStateChanged() => _syncScreenAwake();

  void _syncScreenAwake() {
    final status = _engine.microphoneStatus.value;
    final recording =
        status == MicrophoneStatus.starting ||
        status == MicrophoneStatus.listening ||
        status == MicrophoneStatus.voiceDetected ||
        status == MicrophoneStatus.silence;
    _screenAwake.update(
      recording: recording,
      playing: _playback.isPlaying.value,
      practicing: _practiceActive,
    );
  }

  void _practicePitchChanged() {
    if (!_practiceActive) return;
    final session = _practiceSession;
    if (session == null) return;
    session.pitchToleranceCents = _engine.settings.value.pitchToleranceCents;
    final update = session.process(
      _engine.livePitch.value,
      voiceDetected:
          _engine.microphoneStatus.value == MicrophoneStatus.voiceDetected,
    );
    _practiceProgress.value = session.progress;
    if (update == null) return;
    _engine.notationCursorTick.value = update.cursorTick;
    if (update.completed) unawaited(_stopPractice(completed: true));
  }

  void _compositionChanged() {
    _scheduleCursorScroll();
  }

  void _notationCursorChanged() => _scheduleCursorScroll();

  void _scheduleCursorScroll() {
    if (_cursorScrollScheduled) return;
    _cursorScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cursorScrollScheduled = false;
      if (!mounted || !_scoreScroll.hasClients) return;
      final composition = _engine.composition.value;
      final cursorX = ScoreLayout.cursorX(
        composition,
        _engine.notationCursorTick.value,
      );
      final position = _scoreScroll.position;
      final target = ScoreLayout.scrollOffsetToRevealCursor(
        cursorX: cursorX,
        currentOffset: position.pixels,
        viewportWidth: position.viewportDimension,
        maxScrollExtent: position.maxScrollExtent,
      );
      if (target != null) {
        _scoreScroll.jumpTo(target);
      }
    });
  }

  void _playbackPositionChanged() {
    // Seeking while stopped is coordinated explicitly by the score cursor.
    // Ignore native stop/reset events so they cannot jump the selection to 0.
    if (!_playback.isPlaying.value) return;
    final composition = _engine.composition.value;
    final ticks = ScoreLayout.ticksAt(
      _playback.position.value,
      composition.tempoBpm,
    );
    _engine.notationCursorTick.value = ticks.clamp(
      0,
      ScoreLayout.scoreEndTick(composition),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_stopPlayback(resumeListening: false));
      unawaited(_pauseRecording());
    } else if (state == AppLifecycleState.resumed && _practiceActive) {
      unawaited(_resumePracticeListening());
    } else if (state == AppLifecycleState.resumed && !_pausedByUser) {
      unawaited(_startRecordingAtCursor());
    }
  }

  Future<void> _leave() async {
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false, resetCursor: true);
    await _pauseRecording();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clear() async {
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false, resetCursor: true);
    if (!mounted) return;
    if (_engine.rawEvents.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear the sheet?'),
          content: const Text(
            'All transcribed notes in this composition will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _engine.clear();
    await _playback.seek(Duration.zero);
    if (_scoreScroll.hasClients) _scoreScroll.jumpTo(0);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_practiceActive) await _stopPractice();
    if (!mounted) return;
    var title = _engine.composition.value.title;
    if (_savePath == null) {
      final controller = TextEditingController(
        text: title == 'Untitled Composition' ? '' : title,
      );
      final selectedTitle = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save composition'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'My composition',
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (selectedTitle == null) return;
      title = selectedTitle;
      _engine.setTitle(title);
    }

    setState(() => _saving = true);
    try {
      if (_engine.microphoneStatus.value != MicrophoneStatus.paused &&
          _engine.microphoneStatus.value != MicrophoneStatus.unavailable) {
        _pausedByUser = true;
        await _pauseRecording();
      }
      final saved = await _storage.save(
        composition: _engine.composition.value,
        rawEvents: _engine.rawEvents,
        existingPath: _savePath,
      );
      _savePath = saved.path;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved “$title” locally as compressed MusicXML.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The composition could not be saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    if (!mounted) return;
    if (_playback.isPlaying.value) {
      await _stopPlayback(resumeListening: true);
      return;
    }
    final hasNotes = _engine.composition.value.measures.any(
      (measure) => measure.notes.isNotEmpty,
    );
    if (!hasNotes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sing a few notes before playing the score.'),
        ),
      );
      return;
    }

    final status = _engine.microphoneStatus.value;
    _resumeListeningAfterPlayback =
        !_pausedByUser &&
        status != MicrophoneStatus.unavailable &&
        status != MicrophoneStatus.paused;
    await _pauseRecording();
    final composition = _engine.composition.value;
    final endTick = ScoreLayout.scoreEndTick(composition);
    var startTick = _engine.notationCursorTick.value;
    if (startTick >= endTick) {
      startTick = 0;
      _engine.notationCursorTick.value = 0;
    }
    final startAt = ScoreLayout.durationAt(startTick, composition.tempoBpm);
    if (_playback.position.value != startAt) {
      await _playback.seek(startAt);
    }
    final started = await _playback.play(composition, startAt: startAt);
    if (!started) await _resumeAfterPlaybackIfNeeded();
  }

  Future<void> _toggleRecording() async {
    if (_practiceActive) {
      await _stopPractice();
      if (mounted) await _startRecordingAtCursor();
      return;
    }
    final status = _engine.microphoneStatus.value;
    final recording =
        status == MicrophoneStatus.listening ||
        status == MicrophoneStatus.voiceDetected ||
        status == MicrophoneStatus.silence;
    if (recording) {
      _pausedByUser = true;
      await _pauseRecording();
      return;
    }
    if (status == MicrophoneStatus.starting ||
        status == MicrophoneStatus.unavailable) {
      return;
    }
    await _startRecordingAtCursor();
  }

  Future<void> _togglePractice() async {
    if (_practiceActive) {
      await _stopPractice();
      return;
    }
    final session = PracticeSession(
      _engine.composition.value,
      pitchStabilityMs: _engine.settings.value.pitchStabilityMs,
      pitchToleranceCents: _engine.settings.value.pitchToleranceCents,
    );
    if (!session.hasTargets) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add some notes before practicing.')),
        );
      }
      return;
    }

    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false, resetCursor: true);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      await _pauseRecording();
    }
    _engine.setCaptureEnabled(false);
    _practiceSession = session;
    _practiceProgress.value = 0;
    _pausedByUser = true;
    if (mounted) setState(() => _practiceActive = true);
    _syncScreenAwake();
    _engine.notationCursorTick.value = session.currentTarget!.startTick;
    await _engine.startListening();
    await _syncMetronome();
  }

  Future<void> _stopPractice({bool completed = false}) async {
    if (!_practiceActive) return;
    if (mounted) setState(() => _practiceActive = false);
    _syncScreenAwake();
    _practiceSession = null;
    _practiceProgress.value = 0;
    await _engine.pauseListening();
    _engine.setCaptureEnabled(true);
    _pausedByUser = true;
    if (completed && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Practice complete!')));
    }
  }

  Future<void> _resumePracticeListening() async {
    if (!_practiceActive) return;
    _engine.setCaptureEnabled(false);
    await _engine.startListening();
    await _syncMetronome();
  }

  Future<void> _movePlaybackCursor(Duration position) async {
    await _notePreview.stop(resetPosition: true);
    if (_practiceActive) return;
    final tick = ScoreLayout.ticksAt(
      position,
      _engine.composition.value.tempoBpm,
    );
    final status = _engine.microphoneStatus.value;
    final recording =
        !_playback.isPlaying.value &&
        status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable;
    if (recording) {
      _engine.beginPunchInAt(tick);
      _pausedByUser = false;
    } else {
      _engine.notationCursorTick.value = tick;
    }
    await _playback.seek(position);
  }

  Future<void> _startRecordingAtCursor() async {
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    _engine.setCaptureEnabled(true);
    _engine.beginPunchInAt(_engine.notationCursorTick.value);
    _pausedByUser = false;
    await _engine.startListening();
    await _syncMetronome();
  }

  Future<void> _showNoteMenu() async {
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      _pausedByUser = true;
      await _pauseRecording();
    }
    if (!mounted) return;

    const pitchNames = [
      'C',
      'C♯',
      'D',
      'D♯',
      'E',
      'F',
      'F♯',
      'G',
      'G♯',
      'A',
      'A♯',
      'B',
    ];
    var pitchClass = 0;
    var octave = 4;
    var noteValue = NoteValue.quarter;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Insert note at cursor',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: pitchClass,
                        decoration: const InputDecoration(labelText: 'Pitch'),
                        items: [
                          for (
                            var index = 0;
                            index < pitchNames.length;
                            index++
                          )
                            DropdownMenuItem(
                              value: index,
                              child: Text(pitchNames[index]),
                            ),
                        ],
                        onChanged: (value) => setSheetState(
                          () => pitchClass = value ?? pitchClass,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: octave,
                        decoration: const InputDecoration(labelText: 'Octave'),
                        items: [
                          for (var value = 1; value <= 7; value++)
                            DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => octave = value ?? octave),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<NoteValue>(
                  initialValue: noteValue,
                  decoration: const InputDecoration(labelText: 'Duration'),
                  items: [
                    for (final value in NoteValue.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => noteValue = value ?? noteValue),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    final midi = (octave + 1) * 12 + pitchClass;
                    _engine.insertManualNote(
                      _engine.notationCursorTick.value,
                      midi,
                      noteValue,
                    );
                    final position = ScoreLayout.durationAt(
                      _engine.notationCursorTick.value,
                      _engine.composition.value.tempoBpm,
                    );
                    unawaited(_playback.seek(position));
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Insert note'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showKeySignatureDialog() async {
    if (_practiceActive) await _stopPractice();
    if (!mounted) return;
    var selected = _engine.composition.value.keySignature;
    final result = await showDialog<KeySignature>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Choose a major key'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final keySignature in KeySignature.values)
                  ListTile(
                    leading: Icon(
                      keySignature == selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(keySignature.label),
                    dense: true,
                    selected: keySignature == selected,
                    onTap: () => setDialogState(() => selected = keySignature),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (result != null) _engine.setKeySignature(result);
  }

  Future<void> _showOctaveRangeDialog() async {
    if (_practiceActive) await _stopPractice();
    if (!mounted) return;
    var selected = _engine.composition.value.octaveRange;
    final result = await showDialog<OctaveRange>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Choose octave range'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final range in OctaveRange.values)
                  ListTile(
                    leading: Icon(
                      range == selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(range.label),
                    subtitle: range == OctaveRange.standard
                        ? const Text('Written and sounding pitch match')
                        : Text(_octaveRangeDescription(range)),
                    dense: true,
                    selected: range == selected,
                    onTap: () => setDialogState(() => selected = range),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result == _engine.composition.value.octaveRange) {
      return;
    }
    final selectedTick = _engine.notationCursorTick.value;
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      _pausedByUser = true;
      await _pauseRecording();
    }
    _engine.setOctaveRange(result);
    _engine.notationCursorTick.value = selectedTick.clamp(
      0,
      _engine.composition.value.editableEndTick,
    );
  }

  String _octaveRangeDescription(OctaveRange range) {
    final octaves = range.semitones.abs() ~/ 12;
    final direction = range.semitones < 0 ? 'lower' : 'higher';
    return '${range.notationLabel} · written notes stay in place · '
        'sounds $octaves octave${octaves == 1 ? '' : 's'} $direction';
  }

  Future<void> _showTimeSignatureDialog() async {
    final composition = _engine.composition.value;
    if (composition.measures.isEmpty) return;
    final selectedTick = _engine.notationCursorTick.value;
    final measureIndex = composition.measureIndexAtTick(selectedTick);
    final measure = composition.measures[measureIndex];
    var beats = measure.effectiveBeats(composition.beatsPerMeasure);
    var beatUnit = measure.effectiveBeatUnit(composition.beatUnit);
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Measure ${measureIndex + 1} time signature'),
          content: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: beats,
                  decoration: const InputDecoration(labelText: 'Beats'),
                  items: [
                    for (var value = 1; value <= 32; value++)
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => beats = value);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text('/', style: TextStyle(fontSize: 28)),
              ),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: beatUnit,
                  decoration: const InputDecoration(labelText: 'Note value'),
                  items: [
                    for (final value in const [1, 2, 4, 8, 16])
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => beatUnit = value);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (beats, beatUnit)),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      _pausedByUser = true;
      await _pauseRecording();
    }
    _engine.setMeasureTimeSignatureAtTick(
      selectedTick,
      beatsPerMeasure: result.$1,
      beatUnit: result.$2,
    );
  }

  Future<void> _showVolumeDialog() async {
    final composition = _engine.composition.value;
    var playbackVolume = composition.playbackVolume;
    var metronomeVolume = composition.metronomeVolume;
    final result = await showDialog<(double, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Audio volumes'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Music playback ${(playbackVolume * 100).round()}%'),
                Slider(
                  value: playbackVolume,
                  divisions: 20,
                  onChanged: (value) =>
                      setDialogState(() => playbackVolume = value),
                ),
                const SizedBox(height: 8),
                Text('Metronome ${(metronomeVolume * 100).round()}%'),
                Slider(
                  value: metronomeVolume,
                  divisions: 20,
                  onChanged: (value) =>
                      setDialogState(() => metronomeVolume = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (playbackVolume, metronomeVolume)),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final wasPlaying = _playback.isPlaying.value;
    final playbackPosition = _playback.position.value;
    _engine.setVolumes(playbackVolume: result.$1, metronomeVolume: result.$2);
    if (wasPlaying) {
      await _playback.stop();
      await _playback.play(
        _engine.composition.value,
        startAt: playbackPosition,
      );
    } else {
      await _syncMetronome();
    }
  }

  Future<void> _pauseRecording() async {
    await _metronome.stop();
    await _engine.pauseListening();
  }

  Future<void> _editSelectedNote({
    int pitchDelta = 0,
    int durationDelta = 0,
  }) async {
    if (_practiceActive) await _stopPractice();
    final selectedTick = _engine.notationCursorTick.value;
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      _pausedByUser = true;
      await _pauseRecording();
    }
    _engine.notationCursorTick.value = selectedTick;
    final edited = _engine.editNoteAtTick(
      selectedTick,
      pitchDelta: pitchDelta,
      durationDelta: durationDelta,
    );
    if (edited == null) return;
    _engine.notationCursorTick.value = selectedTick;

    await _playEditedPreview(
      midiPitch: edited.midiPitch,
      durationTicks: edited.durationTicks,
      isRest: _engine.isRestAtTick(selectedTick),
    );
  }

  Future<void> _toggleSelectedRest() async {
    if (_practiceActive) await _stopPractice();
    final selectedTick = _engine.notationCursorTick.value;
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      _pausedByUser = true;
      await _pauseRecording();
    }
    _engine.notationCursorTick.value = selectedTick;
    final edited = _engine.toggleRestAtTick(selectedTick);
    if (edited == null) return;
    _engine.notationCursorTick.value = selectedTick;
    await _playEditedPreview(
      midiPitch: edited.midiPitch,
      durationTicks: edited.durationTicks,
      isRest: edited.isRest,
    );
  }

  Future<void> _toggleSelectedTie() async {
    if (_practiceActive) await _stopPractice();
    final selectedTick = _engine.notationCursorTick.value;
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      _pausedByUser = true;
      await _pauseRecording();
    }
    _engine.notationCursorTick.value = selectedTick;
    _engine.toggleTieAtTick(selectedTick);
    _engine.notationCursorTick.value = selectedTick;
  }

  Future<void> _removeSelectedNote() async {
    if (_practiceActive) await _stopPractice();
    final selectedTick = _engine.notationCursorTick.value;
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      _pausedByUser = true;
      await _pauseRecording();
    }
    _engine.notationCursorTick.value = selectedTick;
    _engine.removeNoteAtTick(selectedTick);
  }

  Future<void> _insertMeasure() async {
    if (_practiceActive) await _stopPractice();
    final selectedTick = _engine.notationCursorTick.value;
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      _pausedByUser = true;
      await _pauseRecording();
    }
    _engine.notationCursorTick.value = selectedTick;
    _engine.insertMeasureAfterTick(selectedTick);
  }

  Future<void> _playEditedPreview({
    required int midiPitch,
    required int durationTicks,
    required bool isRest,
  }) async {
    final composition = _engine.composition.value;
    await _notePreview.play(
      Composition(
        clef: composition.clef,
        keySignature: composition.keySignature,
        tempoBpm: composition.tempoBpm,
        playbackVolume: composition.playbackVolume,
        measures: [
          Measure(
            index: 0,
            notes: [
              MusicalNote(
                midiPitch: midiPitch,
                startTick: 0,
                durationTicks: durationTicks,
                isRest: isRest,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeMetronomeMode(MetronomeMode mode) async {
    final wasPlaying = _playback.isPlaying.value;
    final playbackPosition = _playback.position.value;
    _engine.setMetronomeMode(mode);
    if (wasPlaying) {
      await _playback.stop();
      await _playback.play(
        _engine.composition.value,
        startAt: playbackPosition,
      );
      return;
    }
    await _syncMetronome();
  }

  Future<void> _syncMetronome() async {
    final composition = _engine.composition.value;
    final status = _engine.microphoneStatus.value;
    final recording =
        status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable &&
        status != MicrophoneStatus.starting;
    if (composition.metronomeMode == MetronomeMode.off ||
        !recording ||
        _playback.isPlaying.value) {
      await _metronome.stop();
      return;
    }
    try {
      await _metronome.start(
        composition.tempoBpm,
        composition.metronomeMode,
        volume: composition.metronomeVolume,
      );
    } catch (_) {
      _engine.setMetronomeMode(MetronomeMode.off);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The metronome could not start.')),
        );
      }
    }
  }

  void _playbackCompleted() {
    _engine.notationCursorTick.value = ScoreLayout.scoreEndTick(
      _engine.composition.value,
    );
    unawaited(_resumeAfterPlaybackIfNeeded());
  }

  Future<void> _stopPlayback({
    required bool resumeListening,
    bool resetCursor = false,
  }) async {
    final shouldResume = resumeListening && _resumeListeningAfterPlayback;
    _resumeListeningAfterPlayback = false;
    await _playback.stop(resetPosition: resetCursor);
    if (shouldResume && mounted) await _startRecordingAtCursor();
  }

  Future<void> _resumeAfterPlaybackIfNeeded() async {
    final shouldResume = _resumeListeningAfterPlayback;
    _resumeListeningAfterPlayback = false;
    if (shouldResume && mounted) await _startRecordingAtCursor();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          title: ValueListenableBuilder<Composition>(
            valueListenable: _engine.composition,
            builder: (context, composition, _) =>
                Text(composition.title, overflow: TextOverflow.ellipsis),
          ),
          actions: [
            IconButton(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              tooltip: 'Save Composition',
            ),
            IconButton(
              onPressed: _showNoteMenu,
              icon: const Icon(Icons.note_add_outlined),
              tooltip: 'Insert Note',
            ),
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear Sheet',
            ),
            IconButton(
              onPressed: () {
                setState(() => _settingsExpanded = !_settingsExpanded);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_pageScroll.hasClients) {
                    _pageScroll.animateTo(
                      _pageScroll.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                    );
                  }
                });
              },
              icon: const Icon(Icons.tune),
              tooltip: 'Voice Settings',
            ),
          ],
        ),
        body: ListView(
          controller: _pageScroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            ValueListenableBuilder<Composition>(
              valueListenable: _engine.composition,
              builder: (context, composition, _) => ValueListenableBuilder<int>(
                valueListenable: _engine.notationCursorTick,
                builder: (context, cursorTick, _) => _CompositionHeader(
                  composition: composition,
                  selectedMeasureIndex: composition.measureIndexAtTick(
                    cursorTick,
                  ),
                  onKeySignaturePressed: _showKeySignatureDialog,
                  onOctaveRangePressed: _showOctaveRangeDialog,
                  onTimeSignaturePressed: _showTimeSignatureDialog,
                  onVolumesPressed: _showVolumeDialog,
                  onMetronomeChanged: (mode) =>
                      unawaited(_changeMetronomeMode(mode)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 250,
                child: ValueListenableBuilder<Composition>(
                  valueListenable: _engine.composition,
                  builder: (context, composition, _) =>
                      ValueListenableBuilder<int>(
                        valueListenable: _engine.notationCursorTick,
                        builder: (context, cursorTick, _) => Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PracticePitchGauge(
                              active: _practiceActive,
                              targetMidiPitch: _practiceSession
                                  ?.currentTarget
                                  ?.soundingMidiPitch,
                              pitch: _engine.livePitch,
                              microphoneStatus: _engine.microphoneStatus,
                              settings: _engine.settings,
                            ),
                            Expanded(
                              child: ScoreView(
                                composition: composition,
                                scrollController: _scoreScroll,
                                selectedEventIndex: _engine.eventIndexAtTick(
                                  cursorTick,
                                ),
                                playbackPosition: ScoreLayout.durationAt(
                                  cursorTick,
                                  composition.tempoBpm,
                                ),
                                showPlaybackCursor: true,
                                practiceTargetTick:
                                    _practiceSession?.currentTarget?.startTick,
                                practiceProgress: _practiceProgress,
                                onCursorMoved: (position) =>
                                    unawaited(_movePlaybackCursor(position)),
                              ),
                            ),
                          ],
                        ),
                      ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<Composition>(
              valueListenable: _engine.composition,
              builder: (context, _, _) => ValueListenableBuilder<int>(
                valueListenable: _engine.notationCursorTick,
                builder: (context, cursorTick, _) => _NoteEditControls(
                  hasEvent: _engine.eventIndexAtTick(cursorTick) != null,
                  isRest: _engine.isRestAtTick(cursorTick),
                  canToggleRest: _engine.canToggleRestAtTick(cursorTick),
                  canToggleTie: _engine.canToggleTieAtTick(cursorTick),
                  isTied: _engine.isTiedAtTick(cursorTick),
                  onPitchUp: () => unawaited(_editSelectedNote(pitchDelta: 1)),
                  onPitchDown: () =>
                      unawaited(_editSelectedNote(pitchDelta: -1)),
                  onShorter: () =>
                      unawaited(_editSelectedNote(durationDelta: -1)),
                  onLonger: () =>
                      unawaited(_editSelectedNote(durationDelta: 1)),
                  onToggleRest: () => unawaited(_toggleSelectedRest()),
                  onToggleTie: () => unawaited(_toggleSelectedTie()),
                  onRemove: () => unawaited(_removeSelectedNote()),
                  onInsertMeasure: () => unawaited(_insertMeasure()),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<MicrophoneStatus>(
              valueListenable: _engine.microphoneStatus,
              builder: (context, status, _) => ValueListenableBuilder<bool>(
                valueListenable: _playback.isPlaying,
                builder: (context, playing, _) {
                  final recording =
                      !_practiceActive &&
                      (status == MicrophoneStatus.listening ||
                          status == MicrophoneStatus.voiceDetected ||
                          status == MicrophoneStatus.silence);
                  return _TransportControls(
                    recording: recording,
                    playing: playing,
                    practicing: _practiceActive,
                    recordEnabled:
                        status != MicrophoneStatus.starting &&
                        status != MicrophoneStatus.unavailable,
                    practiceEnabled:
                        status != MicrophoneStatus.starting &&
                        status != MicrophoneStatus.unavailable,
                    onRecord: () => unawaited(_toggleRecording()),
                    onPlay: () => unawaited(_togglePlayback()),
                    onPractice: () => unawaited(_togglePractice()),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Tap anywhere on the staff to place the cursor. Recording stays active and continues overwriting from the selected note.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ),
            const SizedBox(height: 10),
            LivePitchMonitor(
              status: _engine.microphoneStatus,
              pitch: _engine.livePitch,
              durationMs: _engine.currentNoteDurationMs,
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<MicrophoneStatus>(
              valueListenable: _engine.microphoneStatus,
              builder: (context, status, _) =>
                  status == MicrophoneStatus.unavailable
                  ? Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.mic_off),
                        title: const Text('Microphone unavailable'),
                        subtitle: const Text(
                          'Allow microphone access in system settings, then try again.',
                        ),
                        trailing: TextButton(
                          onPressed: _startRecordingAtCursor,
                          child: const Text('Retry'),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Card(
              child: ExpansionTile(
                key: ValueKey(_settingsExpanded),
                initiallyExpanded: _settingsExpanded,
                onExpansionChanged: (value) => _settingsExpanded = value,
                leading: const Icon(Icons.graphic_eq),
                title: const Text('Voice Detection Settings'),
                subtitle: const Text(
                  'Changes apply while the microphone is running',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                children: [
                  ValueListenableBuilder(
                    valueListenable: _engine.settings,
                    builder: (context, value, _) => VoiceSettingsPanel(
                      value: value,
                      onChanged: (next) =>
                          unawaited(_engine.updateSettings(next)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.composition.removeListener(_compositionChanged);
    _engine.notationCursorTick.removeListener(_notationCursorChanged);
    _engine.microphoneStatus.removeListener(_microphoneStatusChanged);
    _engine.livePitch.removeListener(_practicePitchChanged);
    _playback.position.removeListener(_playbackPositionChanged);
    _playback.isPlaying.removeListener(_transportWakeStateChanged);
    _scoreScroll.dispose();
    _pageScroll.dispose();
    _practiceProgress.dispose();
    unawaited(_playback.dispose());
    unawaited(_notePreview.dispose());
    unawaited(_metronome.dispose());
    unawaited(_screenAwake.dispose());
    unawaited(_engine.dispose());
    super.dispose();
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.recording,
    required this.playing,
    required this.practicing,
    required this.recordEnabled,
    required this.practiceEnabled,
    required this.onRecord,
    required this.onPlay,
    required this.onPractice,
  });

  final bool recording;
  final bool playing;
  final bool practicing;
  final bool recordEnabled;
  final bool practiceEnabled;
  final VoidCallback onRecord;
  final VoidCallback onPlay;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _TransportButton(
          key: const ValueKey('record-transport'),
          label: recording ? 'Stop' : 'Record',
          semanticsLabel: recording ? 'Stop recording' : 'Start recording',
          icon: recording
              ? Icons.stop_rounded
              : Icons.fiber_manual_record_rounded,
          active: recording,
          enabled: recordEnabled,
          activeColor: const Color(0xffd9384e),
          onPressed: onRecord,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _TransportButton(
          key: const ValueKey('play-transport'),
          label: playing ? 'Stop' : 'Play',
          semanticsLabel: playing ? 'Stop playback' : 'Play score',
          icon: playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          active: playing,
          enabled: true,
          activeColor: const Color(0xff16865a),
          onPressed: onPlay,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _TransportButton(
          key: const ValueKey('practice-transport'),
          label: practicing ? 'Stop' : 'Practice',
          semanticsLabel: practicing ? 'Stop practice' : 'Start practice',
          icon: practicing ? Icons.stop_rounded : Icons.school_rounded,
          active: practicing,
          enabled: practiceEnabled,
          activeColor: const Color(0xff6c55c7),
          onPressed: onPractice,
        ),
      ),
    ],
  );
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.icon,
    required this.active,
    required this.enabled,
    required this.activeColor,
    required this.onPressed,
  });

  final String label;
  final String semanticsLabel;
  final IconData icon;
  final bool active;
  final bool enabled;
  final Color activeColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = active
        ? Colors.white
        : enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withAlpha(90);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [activeColor.withAlpha(225), activeColor],
                )
              : null,
          color: active ? null : theme.colorScheme.surface,
          border: Border.all(
            color: active
                ? activeColor
                : theme.colorScheme.outlineVariant.withAlpha(190),
          ),
          boxShadow: [
            BoxShadow(
              color: active
                  ? activeColor.withAlpha(60)
                  : Colors.black.withAlpha(12),
              blurRadius: active ? 16 : 8,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 62,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: theme.textTheme.titleSmall!.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                    child: Text(label),
                  ),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      icon,
                      key: ValueKey(icon),
                      color: foreground,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteEditControls extends StatelessWidget {
  const _NoteEditControls({
    required this.hasEvent,
    required this.isRest,
    required this.canToggleRest,
    required this.canToggleTie,
    required this.isTied,
    required this.onPitchUp,
    required this.onPitchDown,
    required this.onShorter,
    required this.onLonger,
    required this.onToggleRest,
    required this.onToggleTie,
    required this.onRemove,
    required this.onInsertMeasure,
  });

  final bool hasEvent;
  final bool isRest;
  final bool canToggleRest;
  final bool canToggleTie;
  final bool isTied;
  final VoidCallback onPitchUp;
  final VoidCallback onPitchDown;
  final VoidCallback onShorter;
  final VoidCallback onLonger;
  final VoidCallback onToggleRest;
  final VoidCallback onToggleTie;
  final VoidCallback onRemove;
  final VoidCallback onInsertMeasure;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: hasEvent && !isRest ? onPitchDown : null,
              icon: const Icon(Icons.arrow_downward),
              tooltip: 'Down one semitone',
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: hasEvent && !isRest ? onPitchUp : null,
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Up one semitone',
            ),
            const SizedBox(height: 28, child: VerticalDivider(width: 12)),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: hasEvent ? onShorter : null,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Shorter note',
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: hasEvent ? onLonger : null,
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'Longer note',
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: canToggleRest ? onToggleRest : null,
              icon: isRest
                  ? const Icon(Icons.music_note)
                  : const RestSymbolIcon(size: 23),
              tooltip: isRest ? 'Change to first-line note' : 'Change to rest',
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: canToggleTie || isTied ? onToggleTie : null,
              icon: Icon(isTied ? Icons.link_off : Icons.link),
              tooltip: isTied ? 'Remove tie' : 'Tie to next note',
            ),
            const SizedBox(height: 28, child: VerticalDivider(width: 12)),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: hasEvent ? onRemove : null,
              icon: const Icon(Icons.close_rounded),
              color: Theme.of(context).colorScheme.error,
              tooltip: 'Remove selected note or rest',
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: onInsertMeasure,
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Insert blank measure after current measure',
            ),
          ],
        ),
      ),
    ),
  );
}

class _CompositionHeader extends StatelessWidget {
  const _CompositionHeader({
    required this.composition,
    required this.selectedMeasureIndex,
    required this.onKeySignaturePressed,
    required this.onOctaveRangePressed,
    required this.onTimeSignaturePressed,
    required this.onVolumesPressed,
    required this.onMetronomeChanged,
  });
  final Composition composition;
  final int selectedMeasureIndex;
  final VoidCallback onKeySignaturePressed;
  final VoidCallback onOctaveRangePressed;
  final VoidCallback onTimeSignaturePressed;
  final VoidCallback onVolumesPressed;
  final ValueChanged<MetronomeMode> onMetronomeChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      _chip(
        Icons.music_note,
        composition.clef == ClefType.treble ? 'Treble clef' : 'Bass clef',
      ),
      ActionChip(
        avatar: const Icon(Icons.swap_vert, size: 16),
        label: Text(composition.octaveRange.label),
        onPressed: onOctaveRangePressed,
        visualDensity: VisualDensity.compact,
      ),
      ActionChip(
        avatar: const Icon(Icons.key, size: 16),
        label: Text(composition.keySignature.label),
        onPressed: onKeySignaturePressed,
        visualDensity: VisualDensity.compact,
      ),
      ActionChip(
        avatar: const Icon(Icons.timer_outlined, size: 16),
        label: Text(
          'Measure ${selectedMeasureIndex + 1}: '
          '${composition.measures[selectedMeasureIndex].effectiveBeats(composition.beatsPerMeasure)}/'
          '${composition.measures[selectedMeasureIndex].effectiveBeatUnit(composition.beatUnit)}',
        ),
        onPressed: onTimeSignaturePressed,
        visualDensity: VisualDensity.compact,
      ),
      _chip(Icons.speed, '${composition.tempoBpm} BPM'),
      _chip(
        Icons.grid_view,
        '${composition.measures.length} measure${composition.measures.length == 1 ? '' : 's'}',
      ),
      _chip(Icons.straighten, 'Fixed tempo'),
      ActionChip(
        avatar: Icon(
          composition.metronomeMode == MetronomeMode.off
              ? Icons.music_off
              : composition.metronomeMode == MetronomeMode.single
              ? Icons.volume_down
              : Icons.music_note,
          size: 16,
        ),
        label: Text(composition.metronomeMode.label),
        onPressed: () => onMetronomeChanged(composition.metronomeMode.next),
        visualDensity: VisualDensity.compact,
      ),
      ActionChip(
        avatar: const Icon(Icons.volume_up, size: 16),
        label: const Text('Volumes'),
        onPressed: onVolumesPressed,
        visualDensity: VisualDensity.compact,
      ),
    ],
  );

  Widget _chip(IconData icon, String label) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}
