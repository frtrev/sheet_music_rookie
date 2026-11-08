import '../l10n/l10n.dart';
import '../widgets/language_selector.dart';
import '../models/playback_instrument.dart';
import '../audio/general_user_soundfont.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/microphone_service.dart';
import '../models/composition.dart';
import '../models/phrase_draft.dart';
import '../widgets/phrase_review_panel.dart';
import '../models/measure.dart';
import '../models/measure_marks.dart';
import '../widgets/measure_mark_icon.dart';
import '../models/musical_note.dart';
import '../models/raw_note_event.dart';
import '../models/voice_detection_settings.dart';
import '../notation/rest_symbol.dart';
import '../notation/score_renderer.dart';
import '../services/composition_storage_service.dart';
import '../services/melody_test_service.dart';
import '../services/metronome_service.dart';
import '../services/practice_service.dart';
import '../services/screen_awake_service.dart';
import '../services/score_playback_service.dart';
import '../services/settings_service.dart';
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
  late final Ticker _testCursorTicker;
  final ScreenAwakeService _screenAwake = ScreenAwakeService();
  final CompositionStorageService _storage = CompositionStorageService();
  final GlobalKey<ScoreViewState> _scoreViewKey = GlobalKey<ScoreViewState>();
  bool _lyricEditing = false;
  final SettingsService _settings = SettingsService();
  bool _noteTapPlayback = true;
  bool _noteTapPreferenceChanged = false;
  final ScrollController _scoreScroll = ScrollController();
  final ScrollController _pageScroll = ScrollController();
  bool _pausedByUser = true;
  bool _settingsExpanded = false;
  bool _resumeListeningAfterPlayback = false;
  bool _cursorScrollScheduled = false;
  bool _manualCursorMoveInProgress = false;
  int _cursorScrollRequestId = 0;
  bool _saving = false;
  bool _leaving = false;
  late bool _importPending;
  bool _historyBusy = false;
  bool _practiceActive = false;
  bool _testActive = false;
  bool _testStopping = false;
  PracticeSession? _practiceSession;
  MelodyTestSession? _testSession;
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
    _importPending =
        widget.initialComposition != null && widget.savePath == null;
    _playback = ScorePlaybackService()..onComplete = _playbackCompleted;
    _notePreview = ScorePlaybackService();
    _metronome = MetronomeService();
    _testCursorTicker = Ticker(_testCursorFrame);
    _playback.position.addListener(_playbackPositionChanged);
    _playback.isPlaying.addListener(_transportWakeStateChanged);
    _engine.composition.addListener(_compositionChanged);
    _engine.notationCursorTick.addListener(_notationCursorChanged);
    _engine.microphoneStatus.addListener(_microphoneStatusChanged);
    _engine.latestAudioFrame.addListener(_practiceFrameChanged);
    _engine.phraseDraft.addListener(_phraseChanged);
    unawaited(_engine.initialize());
    unawaited(_loadNoteTapPlayback());
  }

  void _microphoneStatusChanged() {
    final status = _engine.microphoneStatus.value;
    if (status == MicrophoneStatus.paused ||
        status == MicrophoneStatus.unavailable) {
      unawaited(_metronome.stop());
    }
    _syncScreenAwake();
  }

  void _phraseChanged() {
    final draft = _engine.phraseDraft.value;
    if (draft == null || draft.preview == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scoreScroll.hasClients ||
          _engine.phraseDraft.value != draft) {
        return;
      }
      final tick = draft.stage == PhraseStage.review
          ? draft.startTick
          : (draft.trace.isEmpty ? draft.startTick : draft.trace.last.tick);
      final target = ScoreLayout.scrollOffsetToFollowCursor(
        cursorX: ScoreLayout.playbackCursorX(draft.preview!, tick),
        currentOffset: _scoreScroll.offset,
        viewportWidth: _scoreScroll.position.viewportDimension,
        maxScrollExtent: _scoreScroll.position.maxScrollExtent,
        followFraction: _engine.settings.value.cursorFollowFraction,
      );
      if (target != null) _scoreScroll.jumpTo(target);
    });
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
      practicing: _practiceActive || _testActive,
    );
  }

  void _practiceFrameChanged() {
    final frame = _engine.latestAudioFrame.value;
    if (frame == null) return;
    if (_testActive && !_testStopping) {
      final session = _testSession;
      if (session != null) {
        final voiceDetected =
            _engine.microphoneStatus.value == MicrophoneStatus.voiceDetected;
        session.addFrame(
          frame,
          pitch: voiceDetected ? _engine.livePitch.value : null,
          voiceDetected: voiceDetected,
        );
        if (session.timelineStarted && !_testCursorTicker.isActive) {
          _testCursorTicker.start();
        }
      }
      return;
    }
    if (!_practiceActive) return;
    final session = _practiceSession;
    if (session == null) return;
    _syncPracticeSettings(session);
    final voiceDetected =
        _engine.microphoneStatus.value == MicrophoneStatus.voiceDetected;
    final update = session.process(
      voiceDetected ? _engine.livePitch.value : null,
      voiceDetected: voiceDetected,
      timestampMs: frame.timestampMs,
    );
    _applyPracticeUpdate(session, update);
  }

  void _testCursorFrame(Duration elapsed) {
    if (!_testActive || _testStopping) return;
    final session = _testSession;
    if (session == null || !session.timelineStarted) return;
    _engine.notationCursorTick.value = session.cursorTickAt(elapsed);
    if (session.hasReachedEnd(elapsed)) {
      _testCursorTicker.stop();
      unawaited(_stopTest(showResults: true));
    }
  }

  void _syncPracticeSettings(PracticeSession session) {
    final settings = _engine.settings.value;
    session
      ..pitchToleranceCents = settings.pitchToleranceCents
      ..articulationGapMs = settings.articulationGapMs
      ..difficulty = settings.practiceDifficulty;
  }

  void _applyPracticeUpdate(PracticeSession session, PracticeUpdate? update) {
    _practiceProgress.value = session.progress;
    if (update == null) return;
    _engine.notationCursorTick.value = session.sourceTickAt(update.cursorTick);
    if (update.completed) unawaited(_stopPractice(completed: true));
  }

  void _compositionChanged() {
    if (_shouldFollowCursor && !_manualCursorMoveInProgress) {
      _scheduleCursorScroll();
    }
  }

  void _notationCursorChanged() {
    if (_shouldFollowCursor && !_manualCursorMoveInProgress) {
      // Cursor and viewport must move before the same frame is drawn. Waiting
      // until post-frame briefly displays the new cursor at the old offset.
      _followCursor();
    }
  }

  void _followCursor() {
    if (!mounted || !_scoreScroll.hasClients || !_shouldFollowCursor) return;
    final position = _scoreScroll.position;
    if (!position.hasContentDimensions) return;
    final composition = _engine.composition.value;
    final cursorX = ScoreLayout.playbackCursorX(
      composition,
      _engine.notationCursorTick.value,
    );
    final target = ScoreLayout.scrollOffsetToFollowCursor(
      cursorX: cursorX,
      currentOffset: position.pixels,
      viewportWidth: position.viewportDimension,
      maxScrollExtent: position.maxScrollExtent,
      followFraction: _engine.settings.value.cursorFollowFraction,
    );
    if (target != null && (target - position.pixels).abs() > .01) {
      _scoreScroll.jumpTo(target);
    }
  }

  bool get _shouldFollowCursor {
    final status = _engine.microphoneStatus.value;
    final recording =
        status == MicrophoneStatus.listening ||
        status == MicrophoneStatus.voiceDetected ||
        status == MicrophoneStatus.silence;
    return recording ||
        _playback.isPlaying.value ||
        _practiceActive ||
        _testActive;
  }

  void _scheduleCursorScroll() {
    if (_cursorScrollScheduled) return;
    _cursorScrollScheduled = true;
    final requestId = ++_cursorScrollRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (requestId != _cursorScrollRequestId) return;
      _cursorScrollScheduled = false;
      _followCursor();
    });
  }

  void _cancelAutomaticCursorScroll() {
    _cursorScrollRequestId++;
    _cursorScrollScheduled = false;
  }

  void _playbackPositionChanged() {
    // Seeking while stopped is coordinated explicitly by the score cursor.
    // Ignore native stop/reset events so they cannot jump the selection to 0.
    if (!_playback.isPlaying.value) return;
    final composition = _engine.composition.value;
    final ticks = _playback.scoreTickAt(
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
      if (_testActive) {
        unawaited(_stopTest(showResults: false));
        return;
      }
      unawaited(_stopPlayback(resumeListening: false));
      unawaited(_pauseRecording());
    } else if (state == AppLifecycleState.resumed && _practiceActive) {
      unawaited(_resumePracticeListening());
    } else if (state == AppLifecycleState.resumed && !_pausedByUser) {
      unawaited(_startRecordingAtCursor());
    }
  }

  Future<void> _leave() async {
    _scoreViewKey.currentState?.finishLyricEditing();
    if (_leaving || _saving) return;
    _leaving = true;
    try {
      if (_testActive) await _stopTest(showResults: false);
      if (_practiceActive) await _stopPractice();
      _pausedByUser = true;
      await _notePreview.stop(resetPosition: true);
      await _stopPlayback(resumeListening: false);
      await _pauseRecording();
      if (!mounted) return;
      if (_resolvePhraseFirst()) return;
      if (_importPending || _engine.hasUnsavedChanges) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              _importPending
                  ? context.l10n.saveImportedScore
                  : context.l10n.unsavedChanges,
            ),
            content: Text(
              _importPending
                  ? context
                        .l10n
                        .thisImportedScoreHasNotBeenSavedToYourLibrarySaveItBeforeLeaving
                  : context
                        .l10n
                        .yourScoreHasUnsavedChangesSaveThemBeforeLeaving,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'stay'),
                child: Text(context.l10n.keepEditing),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(context.l10n.discard),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: Text(context.l10n.saveLeave),
              ),
            ],
          ),
        );
        if (!mounted || choice == null || choice == 'stay') return;
        if (choice == 'save') {
          await _save();
          if (!mounted || _importPending || _engine.hasUnsavedChanges) return;
        }
      }
      if (mounted) Navigator.pop(context);
    } finally {
      _leaving = false;
    }
  }

  Future<void> _clear() async {
    _scoreViewKey.currentState?.finishLyricEditing();
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false, resetCursor: true);
    if (!mounted) return;
    if (_engine.rawEvents.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.clearTheSheet),
          content: Text(
            context.l10n.allTranscribedNotesInThisCompositionWillBeRemoved,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.clear),
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
    _scoreViewKey.currentState?.finishLyricEditing();
    if (_resolvePhraseFirst()) return;
    if (_saving) return;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    if (!mounted) return;
    var title = _engine.composition.value.title;
    if (_savePath == null) {
      final controller = TextEditingController(
        text: title == 'Untitled Composition' ? '' : title,
      );
      final titleRoute = DialogRoute<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.saveComposition),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: context.l10n.title,
              hintText: context.l10n.myComposition,
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
              },
              child: Text(context.l10n.save),
            ),
          ],
        ),
      );
      final selectedTitle = await Navigator.of(context).push(titleRoute);
      await titleRoute.completed;
      controller.dispose();
      if (selectedTitle == null || !mounted) return;
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
      final scoreToSave = _engine.composition.value;
      final eventsToSave = List<RawNoteEvent>.of(_engine.rawEvents);
      final saved = await _storage.save(
        composition: scoreToSave,
        rawEvents: eventsToSave,
        existingPath: _savePath,
      );
      _savePath = saved.path;
      _engine.markSaved(scoreToSave, eventsToSave);
      _importPending = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.savedLocally(title))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.theCompositionCouldNotBeSaved)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
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
        SnackBar(
          content: Text(context.l10n.singAFewNotesBeforePlayingTheScore),
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
    if (_resolvePhraseFirst()) return;
    final composition = _engine.composition.value;
    final endTick = ScoreLayout.scoreEndTick(composition);
    var startTick = _engine.notationCursorTick.value;
    if (startTick >= endTick) {
      startTick = 0;
      _engine.notationCursorTick.value = 0;
    }
    final startAt = ScoreLayout.durationAt(startTick, composition.tempoBpm);
    final started = await _playback.play(composition, startAt: startAt);
    if (!started) await _resumeAfterPlaybackIfNeeded();
  }

  Future<void> _toggleRecording() async {
    if (_testActive) await _stopTest(showResults: false);
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
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) {
      await _stopPractice();
      return;
    }
    final session = PracticeSession(
      _engine.composition.value,
      pitchStabilityMs: _engine.settings.value.pitchStabilityMs,
      pitchToleranceCents: _engine.settings.value.pitchToleranceCents,
      articulationGapMs: _engine.settings.value.articulationGapMs,
      difficulty: _engine.settings.value.practiceDifficulty,
    );
    if (!session.hasTargets) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.addSomeNotesBeforePracticing)),
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
      if (_resolvePhraseFirst()) return;
    }
    _engine.setCaptureEnabled(false);
    _practiceSession = session;
    _practiceProgress.value = 0;
    _pausedByUser = true;
    if (mounted) setState(() => _practiceActive = true);
    _syncScreenAwake();
    _engine.notationCursorTick.value = session.sourceTickAt(
      session.currentTarget!.startTick,
    );
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
          .showSnackBar(SnackBar(content: Text(context.l10n.practiceComplete)));
    }
  }

  Future<void> _resumePracticeListening() async {
    if (!_practiceActive) return;
    _engine.setCaptureEnabled(false);
    await _engine.startListening();
    await _syncMetronome();
  }

  Future<void> _toggleTest() async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) {
      await _stopTest(showResults: true);
      return;
    }
    final session = MelodyTestSession(
      _engine.composition.value,
      voicePolish: _engine.settings.value.voicePolish,
    );
    if (!session.hasNotes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.addSomeNotesBeforeStartingATest)),
        );
      }
      return;
    }

    if (_practiceActive) await _stopPractice();
    _testCursorTicker.stop();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false, resetCursor: true);
    final status = _engine.microphoneStatus.value;
    if (status != MicrophoneStatus.paused &&
        status != MicrophoneStatus.unavailable) {
      await _pauseRecording();
      if (_resolvePhraseFirst()) return;
    }
    _engine.setCaptureEnabled(false);
    _testSession = session;
    _pausedByUser = true;
    _engine.notationCursorTick.value = 0;
    if (mounted) setState(() => _testActive = true);
    _syncScreenAwake();
    await _engine.startListening();
    if (_engine.microphoneStatus.value == MicrophoneStatus.unavailable) {
      if (mounted) setState(() => _testActive = false);
      _testSession = null;
      _engine.setCaptureEnabled(true);
      _syncScreenAwake();
    }
  }

  Future<void> _stopTest({required bool showResults}) async {
    if (!_testActive || _testStopping) return;
    _testStopping = true;
    _testCursorTicker.stop();
    final session = _testSession;
    if (mounted) setState(() => _testActive = false);
    _syncScreenAwake();
    await _engine.pauseListening();
    _engine.setCaptureEnabled(true);
    _testSession = null;
    _pausedByUser = true;
    MelodyTestResult? result;
    try {
      result = await session?.finishAsync();
    } finally {
      _testStopping = false;
    }
    if (showResults && result != null && mounted) {
      await _showTestResult(result);
    }
  }

  Future<void> _showTestResult(MelodyTestResult result) async {
    await _notePreview.stop(resetPosition: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          result.score >= 80
              ? Icons.emoji_events_rounded
              : Icons.insights_rounded,
          size: 38,
        ),
        title: Text(context.l10n.melodyTestResult),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${result.score}',
              style: Theme.of(dialogContext).textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(dialogContext).colorScheme.primary,
              ),
            ),
            Text(context.l10n.outOf100),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TestScoreDetail(
                  label: context.l10n.pitch,
                  score: result.pitchScore,
                ),
                _TestScoreDetail(
                  label: context.l10n.timing,
                  score: result.timingScore,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: result.matchupWave == null
                ? null
                : () => unawaited(_notePreview.playWave(result.matchupWave!)),
            icon: const Icon(Icons.headphones_rounded),
            label: Text(context.l10n.listenToMatch),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
    await _notePreview.stop(resetPosition: true);
  }

  bool _resolvePhraseFirst() {
    if (_engine.phraseDraft.value == null) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.acceptOrDiscardTheRecordingPhraseBelowTheScoreFirst,
        ),
      ),
    );
    return true;
  }

  Future<void> _loadNoteTapPlayback() async {
    final enabled = await _settings.loadNoteTapPlayback();
    if (!mounted || _noteTapPreferenceChanged) return;
    setState(() => _noteTapPlayback = enabled);
  }

  Future<void> _toggleNoteTapPlayback() async {
    _noteTapPreferenceChanged = true;
    final enabled = !_noteTapPlayback;
    setState(() => _noteTapPlayback = enabled);
    await Future.wait([
      _settings.saveNoteTapPlayback(enabled),
      if (!enabled) _notePreview.stop(resetPosition: true),
    ]);
  }

  Future<void> _previewNoteAtTick(int tick) async {
    if (!_noteTapPlayback || _playback.isPlaying.value) return;
    final composition = _engine.composition.value;
    for (final measure in composition.measures) {
      final start = composition.measureStartTick(measure.index);
      for (final note in measure.notes) {
        if (tick >= start + note.startTick &&
            tick < start + note.startTick + note.durationTicks) {
          if (note.isRest) return;
          await _playEditedPreview(
            midiPitch: playbackMidiPitch(
              composition,
              note.midiPitch,
              accidental: note.accidental,
            ),
            durationTicks: note.durationTicks,
            isRest: false,
          );
          return;
        }
      }
    }
  }

  Future<void> _movePlaybackCursor(Duration position) async {
    if (_resolvePhraseFirst()) return;
    await _notePreview.stop(resetPosition: true);
    if (_practiceActive || _testActive) return;
    _cancelAutomaticCursorScroll();
    _manualCursorMoveInProgress = true;
    final tick = ScoreLayout.ticksAt(
      position,
      _engine.composition.value.tempoBpm,
    );
    try {
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
      await _playback.seekScore(position, _engine.composition.value.tempoBpm);
      if (mounted && !recording) await _previewNoteAtTick(tick);
    } finally {
      _manualCursorMoveInProgress = false;
    }
  }

  Future<void> _startRecordingAtCursor() async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    _engine.setCaptureEnabled(true);
    _engine.beginPunchInAt(_engine.notationCursorTick.value);
    _pausedByUser = false;
    await _engine.startListening();
    await _syncMetronome();
  }

  Future<void> _prepareScoreSoundChange() async {
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    _pausedByUser = true;
    if (_engine.microphoneStatus.value != MicrophoneStatus.paused) {
      await _pauseRecording();
    }
  }

  Future<void> _showTempoDialog() async {
    if (_resolvePhraseFirst()) return;
    final controller = TextEditingController(
      text: '${_engine.composition.value.tempoBpm}',
    );
    final formKey = GlobalKey<FormState>();
    final tempoRoute = DialogRoute<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.tempo),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.beatsPerMinute,
              helperText: context.l10n.message20400Bpm,
            ),
            validator: (value) {
              final n = int.tryParse(value?.trim() ?? '');
              return n == null || n < 20 || n > 400
                  ? context.l10n.enterAWholeNumberFrom20To400
                  : null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, int.parse(controller.text.trim()));
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, int.parse(controller.text.trim()));
              }
            },
            child: Text(context.l10n.apply),
          ),
        ],
      ),
    );
    final value = await Navigator.of(context).push(tempoRoute);
    await tempoRoute.completed;
    controller.dispose();
    if (value == null ||
        !mounted ||
        value == _engine.composition.value.tempoBpm) {
      return;
    }
    await _prepareScoreSoundChange();
    if (mounted) _engine.setTempoBpm(value);
  }

  Future<void> _showInstrumentDialog() async {
    if (_resolvePhraseFirst()) return;
    final value = await showDialog<PlaybackInstrument>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.playbackInstrument),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(context.l10n.generaluserGsSampledInstrumentsOffline),
          ),
          for (final family in ['Keyboards', 'Strings', 'Winds']) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Text(
                context.l10n.label(family),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final instrument in PlaybackInstrument.values.where(
              (i) => i.family == family,
            ))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, instrument),
                child: Row(
                  children: [
                    Expanded(child: Text(context.l10n.label(instrument.label))),
                    if (instrument ==
                        _engine.composition.value.playbackInstrument)
                      const Icon(Icons.check),
                  ],
                ),
              ),
          ],
          TextButton(
            onPressed: () {
              GeneralUserSoundFont.registerLicenses();
              showLicensePage(
                context: context,
                applicationName: 'Sheet Music Rookie',
              );
            },
            child: Text(context.l10n.soundLibraryLicenses),
          ),
        ],
      ),
    );
    if (value == null ||
        !mounted ||
        value == _engine.composition.value.playbackInstrument) {
      return;
    }
    await _prepareScoreSoundChange();
    if (mounted) _engine.setPlaybackInstrument(value);
  }

  Future<void> _showKeySignatureDialog() async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    if (!mounted) return;
    var selected = _engine.composition.value.keySignature;
    final result = await showDialog<KeySignature>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.chooseAMajorKey),
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
                    title: Text(context.l10n.keyLabel(keySignature)),
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
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(context.l10n.ok),
            ),
          ],
        ),
      ),
    );
    if (result != null) _engine.setKeySignature(result);
  }

  Future<void> _showOctaveRangeDialog() async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    if (!mounted) return;
    var selected = _engine.composition.value.octaveRange;
    final result = await showDialog<OctaveRange>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.chooseOctaveRange),
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
                    title: Text(context.l10n.label(range.label)),
                    subtitle: range == OctaveRange.standard
                        ? Text(context.l10n.writtenAndSoundingPitchMatch)
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
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(context.l10n.ok),
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
    return range.semitones < 0
        ? context.l10n.octaveLower(range.notationLabel, octaves)
        : context.l10n.octaveHigher(range.notationLabel, octaves);
  }

  Future<void> _showTimeSignatureDialog() async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    final composition = _engine.composition.value;
    if (composition.measures.isEmpty) return;
    if (!mounted) return;
    final selectedTick = _engine.notationCursorTick.value;
    final measureIndex = composition.measureIndexAtTick(selectedTick);
    final measure = composition.measures[measureIndex];
    var beats = measure.effectiveBeats(composition.beatsPerMeasure);
    var beatUnit = measure.effectiveBeatUnit(composition.beatUnit);
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.measureTimeSignature(measureIndex + 1)),
          content: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: beats,
                  decoration: InputDecoration(labelText: context.l10n.beats),
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
                  decoration: InputDecoration(
                    labelText: context.l10n.noteValue,
                  ),
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
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (beats, beatUnit)),
              child: Text(context.l10n.ok),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
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
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    final composition = _engine.composition.value;
    if (!mounted) return;
    var playbackVolume = composition.playbackVolume;
    var metronomeVolume = composition.metronomeVolume;
    final result = await showDialog<(double, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.audioVolumes),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.musicVolume((playbackVolume * 100).round())),
                Slider(
                  value: playbackVolume,
                  divisions: 20,
                  onChanged: (value) =>
                      setDialogState(() => playbackVolume = value),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.metronomeVolume((metronomeVolume * 100).round()),
                ),
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
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (playbackVolume, metronomeVolume)),
              child: Text(context.l10n.ok),
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

  Future<void> _changeHistory({required bool redo}) async {
    if (_resolvePhraseFirst()) return;
    if (_historyBusy) return;
    setState(() => _historyBusy = true);
    try {
      if (_testActive) await _stopTest(showResults: false);
      if (_practiceActive) await _stopPractice();
      await _notePreview.stop(resetPosition: true);
      await _stopPlayback(resumeListening: false);
      _pausedByUser = true;
      if (_engine.microphoneStatus.value != MicrophoneStatus.paused) {
        await _pauseRecording();
      }
      _cancelAutomaticCursorScroll();
      if (redo) {
        _engine.redo();
      } else {
        _engine.undo();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scoreScroll.hasClients) return;
        final target = ScoreLayout.scrollOffsetToRevealCursor(
          cursorX: ScoreLayout.cursorX(
            _engine.composition.value,
            _engine.notationCursorTick.value,
          ),
          currentOffset: _scoreScroll.offset,
          viewportWidth: _scoreScroll.position.viewportDimension,
          maxScrollExtent: _scoreScroll.position.maxScrollExtent,
        );
        if (target != null) _scoreScroll.jumpTo(target);
      });
    } finally {
      if (mounted) setState(() => _historyBusy = false);
    }
  }

  Future<void> _editMeasureMark(MeasureEdge edge, bool volta) async {
    _scoreViewKey.currentState?.finishLyricEditing();
    if (_resolvePhraseFirst()) return;
    final tick = _engine.notationCursorTick.value;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    _pausedByUser = true;
    await _pauseRecording();
    if (!mounted) return;
    _engine.editMeasureMarkAtTick(tick, edge: edge, volta: volta);
  }

  Future<bool> _prepareLyricEditing(int tick) async {
    if (_resolvePhraseFirst()) return false;
    if (_testActive) await _stopTest(showResults: false);
    if (_practiceActive) await _stopPractice();
    await _notePreview.stop(resetPosition: true);
    await _stopPlayback(resumeListening: false);
    _pausedByUser = true;
    await _pauseRecording();
    if (!mounted) return false;
    _cancelAutomaticCursorScroll();
    _engine.notationCursorTick.value = tick;
    return true;
  }

  void _editLyrics() {
    final tick = _engine.notationCursorTick.value;
    unawaited(_scoreViewKey.currentState?.startLyricEditing(tick));
  }

  Future<void> _editSelectedNote({
    int pitchDelta = 0,
    int durationDelta = 0,
  }) async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
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
    if (_resolvePhraseFirst()) return;
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

  Future<void> _toggleSelectedRest({bool insertNote = false}) async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
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
    if (_resolvePhraseFirst()) return;
    _engine.notationCursorTick.value = selectedTick;
    final edited = insertNote
        ? _engine.writeNoteAtTick(selectedTick)
        : _engine.writeRestAtTick(selectedTick);
    if (edited == null) return;
    await _playEditedPreview(
      midiPitch: edited.midiPitch,
      durationTicks: edited.durationTicks,
      isRest: edited.isRest,
    );
  }

  Future<void> _toggleSelectedTie() async {
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
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
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
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
    if (_resolvePhraseFirst()) return;
    if (_testActive) await _stopTest(showResults: false);
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
        // Preview pitches are already converted to sounding MIDI.
        keySignature: KeySignature.cMajor,
        tempoBpm: composition.tempoBpm,
        playbackVolume: composition.playbackVolume,
        playbackInstrument: composition.playbackInstrument,
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
          SnackBar(content: Text(context.l10n.theMetronomeCouldNotStart)),
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
            tooltip: context.l10n.back,
          ),
          title: ValueListenableBuilder<Composition>(
            valueListenable: _engine.composition,
            builder: (context, composition, _) => Text(
              context.l10n.sheetTitle(composition.title),
              overflow: TextOverflow.ellipsis,
            ),
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
              tooltip: context.l10n.saveComposition2,
            ),
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: context.l10n.clearSheet,
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
              tooltip: context.l10n.settings,
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
                  onTempoPressed: _showTempoDialog,
                  onInstrumentPressed: _showInstrumentDialog,
                  onMetronomeChanged: (mode) =>
                      unawaited(_changeMetronomeMode(mode)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<PhraseDraft?>(
              valueListenable: _engine.phraseDraft,
              builder: (context, draft, _) => Column(
                children: [
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      height: 350,
                      child: ValueListenableBuilder<Composition>(
                        valueListenable: _engine.composition,
                        builder: (context, composition, _) =>
                            ValueListenableBuilder<int>(
                              valueListenable: _engine.notationCursorTick,
                              builder: (context, cursorTick, _) {
                                final beginnerTest =
                                    _testActive &&
                                    _engine.settings.value.practiceDifficulty ==
                                        PracticeDifficulty.beginner;
                                final gaugeTarget = _practiceActive
                                    ? _practiceSession
                                          ?.currentTarget
                                          ?.soundingMidiPitch
                                    : beginnerTest
                                    ? _testSession?.expectedMidiPitchAtTick(
                                        cursorTick,
                                      )
                                    : null;
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    PracticePitchGauge(
                                      active: _practiceActive || beginnerTest,
                                      targetMidiPitch: gaugeTarget,
                                      pitch: _engine.livePitch,
                                      microphoneStatus:
                                          _engine.microphoneStatus,
                                      settings: _engine.settings,
                                    ),
                                    Expanded(
                                      child: ScoreView(
                                        key: _scoreViewKey,
                                        onLyricChanged: _engine.setLyricAtTick,
                                        onLyricEditing: _prepareLyricEditing,
                                        onLyricEditingChanged: (editing) {
                                          if (mounted) {
                                            setState(
                                              () => _lyricEditing = editing,
                                            );
                                          }
                                        },
                                        composition:
                                            draft?.preview ?? composition,
                                        pitchTrace: draft?.trace ?? const [],
                                        previewStartTick:
                                            draft?.stage == PhraseStage.review
                                            ? draft?.startTick
                                            : null,
                                        previewEndTick:
                                            draft?.stage == PhraseStage.review
                                            ? draft?.endTick
                                            : null,
                                        scrollController: _scoreScroll,
                                        selectedTick: cursorTick,
                                        selectedEventIndex: _engine
                                            .eventIndexAtTick(cursorTick),
                                        playbackPosition:
                                            ScoreLayout.durationAt(
                                              cursorTick,
                                              composition.tempoBpm,
                                            ),
                                        showPlaybackCursor: true,
                                        practiceTargetTick:
                                            _practiceSession?.currentTarget ==
                                                null
                                            ? null
                                            : _practiceSession!.sourceTickAt(
                                                _practiceSession!
                                                    .currentTarget!
                                                    .startTick,
                                              ),
                                        practiceProgress: _practiceProgress,
                                        cursorFollowFraction: _engine
                                            .settings
                                            .value
                                            .cursorFollowFraction,
                                        onCursorMoved: (position) => unawaited(
                                          _movePlaybackCursor(position),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                      ),
                    ),
                  ),
                  if (draft != null)
                    PhraseReviewPanel(
                      draft: draft,
                      onAccept: () => _engine.acceptPhrase(),
                      onDiscard: _engine.discardPhrase,
                      onFinish: () => unawaited(_engine.finishPhrase()),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: _engine.historyRevision,
              builder: (context, _, _) => ValueListenableBuilder<Composition>(
                valueListenable: _engine.composition,
                builder: (context, composition, _) =>
                    ValueListenableBuilder<int>(
                      valueListenable: _engine.notationCursorTick,
                      builder: (context, cursorTick, _) => _NoteEditControls(
                        selectedMeasure: composition.measures.isEmpty
                            ? null
                            : composition.measures[composition
                                  .measureIndexAtTick(cursorTick)],
                        onEditMeasureMark: (edge, volta) =>
                            unawaited(_editMeasureMark(edge, volta)),
                        noteTapPlayback: _noteTapPlayback,
                        onToggleNoteTapPlayback: () =>
                            unawaited(_toggleNoteTapPlayback()),
                        lyricEditing: _lyricEditing,
                        onEditLyrics: _editLyrics,
                        canUndo: !_historyBusy && _engine.canUndo,
                        canRedo: !_historyBusy && _engine.canRedo,
                        onUndo: () => unawaited(_changeHistory(redo: false)),
                        onRedo: () => unawaited(_changeHistory(redo: true)),
                        hasEvent: _engine.eventIndexAtTick(cursorTick) != null,
                        isRest: _engine.isRestAtTick(cursorTick),
                        canToggleRest: _engine.canToggleRestAtTick(cursorTick),
                        canToggleTie: _engine.canToggleTieAtTick(cursorTick),
                        isTied: _engine.isTiedAtTick(cursorTick),
                        onPitchUp: () {
                          if (_scoreViewKey.currentState?.isEditingLyric ??
                              false) {
                            _scoreViewKey.currentState!.moveLyricLine(-1);
                          } else {
                            unawaited(_editSelectedNote(pitchDelta: 1));
                          }
                        },
                        onPitchDown: () {
                          if (_scoreViewKey.currentState?.isEditingLyric ??
                              false) {
                            _scoreViewKey.currentState!.moveLyricLine(1);
                          } else {
                            unawaited(_editSelectedNote(pitchDelta: -1));
                          }
                        },
                        onShorter: () =>
                            unawaited(_editSelectedNote(durationDelta: -1)),
                        onLonger: () =>
                            unawaited(_editSelectedNote(durationDelta: 1)),
                        onToggleNote: () =>
                            unawaited(_toggleSelectedRest(insertNote: true)),
                        onToggleRest: () => unawaited(_toggleSelectedRest()),
                        onToggleTie: () => unawaited(_toggleSelectedTie()),
                        onRemove: () => unawaited(_removeSelectedNote()),
                        onInsertMeasure: () => unawaited(_insertMeasure()),
                      ),
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
                      !_testActive &&
                      (status == MicrophoneStatus.listening ||
                          status == MicrophoneStatus.voiceDetected ||
                          status == MicrophoneStatus.silence);
                  return _TransportControls(
                    recording: recording,
                    playing: playing,
                    practicing: _practiceActive,
                    testing: _testActive,
                    recordEnabled:
                        status != MicrophoneStatus.starting &&
                        status != MicrophoneStatus.unavailable,
                    practiceEnabled:
                        status != MicrophoneStatus.starting &&
                        status != MicrophoneStatus.unavailable,
                    testEnabled:
                        status != MicrophoneStatus.starting &&
                        status != MicrophoneStatus.unavailable,
                    onRecord: () => unawaited(_toggleRecording()),
                    onPlay: () => unawaited(_togglePlayback()),
                    onPractice: () => unawaited(_togglePractice()),
                    onTest: () => unawaited(_toggleTest()),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                context
                    .l10n
                    .tapAnywhereOnTheStaffToPlaceTheCursorRecordingStaysActiveAndContinuesOverwritingFromTheSelectedNote,
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
                        title: Text(context.l10n.microphoneUnavailable),
                        subtitle: Text(
                          context
                              .l10n
                              .allowMicrophoneAccessInSystemSettingsThenTryAgain,
                        ),
                        trailing: TextButton(
                          onPressed: _startRecordingAtCursor,
                          child: Text(context.l10n.retry),
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
                title: Text(context.l10n.settings),
                subtitle: Text(context.l10n.recognitionPracticeAndTestPlayback),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                children: [
                  const LanguageSelector(),
                  ValueListenableBuilder(
                    valueListenable: _engine.settings,
                    builder: (context, value, _) => VoiceSettingsPanel(
                      value: value,
                      onChanged: (next) {
                        if (!_resolvePhraseFirst()) {
                          unawaited(_engine.updateSettings(next));
                        }
                      },
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
    _engine.latestAudioFrame.removeListener(_practiceFrameChanged);
    _engine.phraseDraft.removeListener(_phraseChanged);
    _playback.position.removeListener(_playbackPositionChanged);
    _playback.isPlaying.removeListener(_transportWakeStateChanged);
    _scoreScroll.dispose();
    _pageScroll.dispose();
    _practiceProgress.dispose();
    _testCursorTicker.dispose();
    unawaited(_playback.dispose());
    unawaited(_notePreview.dispose());
    unawaited(_metronome.dispose());
    unawaited(_screenAwake.dispose());
    unawaited(_engine.dispose());
    super.dispose();
  }
}

class _TestScoreDetail extends StatelessWidget {
  const _TestScoreDetail({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$score',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.recording,
    required this.playing,
    required this.practicing,
    required this.testing,
    required this.recordEnabled,
    required this.practiceEnabled,
    required this.testEnabled,
    required this.onRecord,
    required this.onPlay,
    required this.onPractice,
    required this.onTest,
  });

  final bool recording;
  final bool playing;
  final bool practicing;
  final bool testing;
  final bool recordEnabled;
  final bool practiceEnabled;
  final bool testEnabled;
  final VoidCallback onRecord;
  final VoidCallback onPlay;
  final VoidCallback onPractice;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _TransportButton(
          key: const ValueKey('record-transport'),
          label: recording ? context.l10n.stop : context.l10n.record,
          semanticsLabel: recording
              ? context.l10n.stopRecording
              : context.l10n.startRecording,
          icon: recording
              ? Icons.stop_rounded
              : Icons.fiber_manual_record_rounded,
          active: recording,
          enabled: recordEnabled,
          activeColor: const Color(0xffd9384e),
          onPressed: onRecord,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _TransportButton(
          key: const ValueKey('play-transport'),
          label: playing ? context.l10n.stop : context.l10n.play,
          semanticsLabel: playing
              ? context.l10n.stopPlayback
              : context.l10n.playScore,
          icon: playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          active: playing,
          enabled: true,
          activeColor: const Color(0xff16865a),
          onPressed: onPlay,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _TransportButton(
          key: const ValueKey('practice-transport'),
          label: practicing ? context.l10n.stop : context.l10n.practice,
          semanticsLabel: practicing
              ? context.l10n.stopPractice
              : context.l10n.startPractice,
          icon: practicing ? Icons.stop_rounded : Icons.school_rounded,
          active: practicing,
          enabled: practiceEnabled,
          activeColor: const Color(0xff6c55c7),
          onPressed: onPractice,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _TransportButton(
          key: const ValueKey('test-transport'),
          label: testing ? context.l10n.stop : context.l10n.test,
          semanticsLabel: testing
              ? context.l10n.stopMelodyTest
              : context.l10n.startMelodyTest,
          icon: testing ? Icons.stop_rounded : Icons.fact_check_rounded,
          active: testing,
          enabled: testEnabled,
          activeColor: const Color(0xffd47a18),
          onPressed: onTest,
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                      size: 21,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: theme.textTheme.titleSmall!.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, maxLines: 1),
                      ),
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
    required this.selectedMeasure,
    required this.onEditMeasureMark,
    required this.noteTapPlayback,
    required this.onToggleNoteTapPlayback,
    required this.lyricEditing,
    required this.onEditLyrics,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.hasEvent,
    required this.isRest,
    required this.canToggleRest,
    required this.canToggleTie,
    required this.isTied,
    required this.onPitchUp,
    required this.onPitchDown,
    required this.onShorter,
    required this.onLonger,
    required this.onToggleNote,
    required this.onToggleRest,
    required this.onToggleTie,
    required this.onRemove,
    required this.onInsertMeasure,
  });

  final Measure? selectedMeasure;
  final void Function(MeasureEdge edge, bool volta) onEditMeasureMark;
  final bool noteTapPlayback;
  final VoidCallback onToggleNoteTapPlayback;
  final bool lyricEditing;
  final VoidCallback onEditLyrics;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool hasEvent;
  final bool isRest;
  final bool canToggleRest;
  final bool canToggleTie;
  final bool isTied;
  final VoidCallback onPitchUp;
  final VoidCallback onPitchDown;
  final VoidCallback onShorter;
  final VoidCallback onLonger;
  final VoidCallback onToggleNote;
  final VoidCallback onToggleRest;
  final VoidCallback onToggleTie;
  final VoidCallback onRemove;
  final VoidCallback onInsertMeasure;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: IconButton(
                  onPressed: canToggleRest ? onToggleNote : null,
                  icon: const Icon(Icons.music_note),
                  tooltip: hasEvent && !isRest
                      ? context.l10n.playSelectedNote
                      : hasEvent
                      ? context.l10n.changeToFirstLineNote
                      : context.l10n.addOneBeatNoteAtNearestBeat,
                ),
              ),
              Expanded(
                child: IconButton(
                  onPressed: canToggleRest ? onToggleRest : null,
                  icon: const RestSymbolIcon(size: 23),
                  tooltip: hasEvent
                      ? context.l10n.changeToRest
                      : context.l10n.addOneBeatRestAtNearestBeat,
                ),
              ),
              _tool(
                Icons.arrow_downward,
                lyricEditing
                    ? context.l10n.nextLyricLine
                    : context.l10n.downOneSemitone,
                hasEvent && !isRest ? onPitchDown : null,
                keepLyricFocus: lyricEditing,
              ),
              _tool(
                Icons.arrow_upward,
                lyricEditing
                    ? context.l10n.previousLyricLine
                    : context.l10n.upOneSemitone,
                hasEvent && !isRest ? onPitchUp : null,
                keepLyricFocus: lyricEditing,
              ),
              _tool(
                Icons.arrow_back,
                context.l10n.shorterNote,
                hasEvent ? onShorter : null,
              ),
              _tool(
                Icons.arrow_forward,
                context.l10n.longerNote,
                hasEvent ? onLonger : null,
              ),
            ],
          ),
          const Divider(height: 8),
          Row(
            children: [
              _tool(
                Icons.lyrics_outlined,
                context.l10n.editLyrics,
                hasEvent && !isRest ? onEditLyrics : null,
              ),
              _tool(
                noteTapPlayback ? Icons.volume_up : Icons.volume_off,
                noteTapPlayback
                    ? context.l10n.muteTappedNotes
                    : context.l10n.playTappedNotes,
                onToggleNoteTapPlayback,
              ),
              _tool(
                isTied ? Icons.link_off : Icons.link,
                isTied ? context.l10n.removeTie : context.l10n.tieToNextNote,
                canToggleTie || isTied ? onToggleTie : null,
              ),
              _tool(
                Icons.undo_rounded,
                context.l10n.undo,
                canUndo ? onUndo : null,
              ),
              _tool(
                Icons.redo_rounded,
                context.l10n.redo,
                canRedo ? onRedo : null,
              ),
              _tool(
                Icons.add_box_outlined,
                context.l10n.insertBlankMeasureAfterCurrentMeasure,
                onInsertMeasure,
              ),
              _tool(
                Icons.close_rounded,
                context.l10n.removeSelectedNoteOrRest,
                hasEvent ? onRemove : null,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
          ),
          const Divider(height: 8),
          Row(
            children: [
              _measureTool(context, MeasureEdge.left),
              _measureTool(context, MeasureEdge.right),
              _measureTool(context, MeasureEdge.left, volta: true),
              _measureTool(context, MeasureEdge.right, volta: true),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _measureTool(
    BuildContext context,
    MeasureEdge edge, {
    bool volta = false,
  }) {
    final marks = MeasureMarks(selectedMeasure?.barlines ?? const []);
    final number = marks.voltaNumber(edge);
    final active = volta ? number != null : marks.hasRepeat(edge);
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: IconButton(
        key: ValueKey('${edge.name}-${volta ? 'volta' : 'repeat'}'),
        tooltip: volta
            ? (edge == MeasureEdge.left
                  ? context.l10n.leftVolta(number ?? context.l10n.noVolta)
                  : context.l10n.rightVolta(number ?? context.l10n.noVolta))
            : (edge == MeasureEdge.left
                  ? context.l10n.leftRepeat
                  : context.l10n.rightRepeat),
        isSelected: active,
        onPressed: selectedMeasure == null
            ? null
            : () => onEditMeasureMark(edge, volta),
        icon: MeasureMarkIcon(
          edge: edge,
          volta: volta,
          number: number,
          color: selectedMeasure == null
              ? colors.onSurface.withValues(alpha: .38)
              : active
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _tool(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    Color? color,
    bool keepLyricFocus = false,
  }) => Expanded(
    child: TextFieldTapRegion(
      enabled: keepLyricFocus,
      child: ExcludeFocus(
        excluding: keepLyricFocus,
        child: IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: onPressed,
          color: color,
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
    required this.onTempoPressed,
    required this.onInstrumentPressed,
    required this.onMetronomeChanged,
  });
  final Composition composition;
  final int selectedMeasureIndex;
  final VoidCallback onKeySignaturePressed;
  final VoidCallback onOctaveRangePressed;
  final VoidCallback onTimeSignaturePressed;
  final VoidCallback onVolumesPressed;
  final VoidCallback onTempoPressed;
  final VoidCallback onInstrumentPressed;
  final ValueChanged<MetronomeMode> onMetronomeChanged;

  @override
  Widget build(BuildContext context) {
    final labels = <Widget>[
      _chip(
        Icons.music_note,
        context.l10n.clefHeader(context.l10n.label(composition.clef.label)),
      ),
      ActionChip(
        avatar: const Icon(Icons.swap_vert, size: 16),
        label: Text(context.l10n.label(composition.octaveRange.label)),
        onPressed: onOctaveRangePressed,
        visualDensity: VisualDensity.compact,
      ),
      ActionChip(
        avatar: const Icon(Icons.key, size: 16),
        label: Text(context.l10n.keyLabel(composition.keySignature)),
        onPressed: onKeySignaturePressed,
        visualDensity: VisualDensity.compact,
      ),
      ActionChip(
        avatar: const Icon(Icons.timer_outlined, size: 16),
        label: Text(
          context.l10n.measureMeter(
            selectedMeasureIndex + 1,
            composition.measures[selectedMeasureIndex].effectiveBeats(
              composition.beatsPerMeasure,
            ),
            composition.measures[selectedMeasureIndex].effectiveBeatUnit(
              composition.beatUnit,
            ),
          ),
        ),
        onPressed: onTimeSignaturePressed,
        visualDensity: VisualDensity.compact,
      ),
      ActionChip(
        avatar: const Icon(Icons.speed, size: 16),
        label: Text('${composition.tempoBpm} BPM'),
        onPressed: onTempoPressed,
        visualDensity: VisualDensity.compact,
      ),
      _chip(
        Icons.grid_view,
        context.l10n.measureCount(composition.measures.length),
      ),
      ActionChip(
        avatar: const Icon(Icons.piano, size: 16),
        label: Text(context.l10n.label(composition.playbackInstrument.label)),
        onPressed: onInstrumentPressed,
        visualDensity: VisualDensity.compact,
      ),
      ActionChip(
        avatar: Icon(
          composition.metronomeMode == MetronomeMode.off
              ? Icons.music_off
              : composition.metronomeMode == MetronomeMode.single
              ? Icons.volume_down
              : Icons.music_note,
          size: 16,
        ),
        label: Text(context.l10n.label(composition.metronomeMode.label)),
        onPressed: () => onMetronomeChanged(composition.metronomeMode.next),
        visualDensity: VisualDensity.compact,
      ),
      ActionChip(
        avatar: const Icon(Icons.volume_up, size: 16),
        label: Text(context.l10n.volumes),
        onPressed: onVolumesPressed,
        visualDensity: VisualDensity.compact,
      ),
    ];
    return SingleChildScrollView(
      key: const PageStorageKey('composition-label-menu'),
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var start = 0; start < labels.length; start += 3) ...[
            if (start > 0) const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var index = start;
                  index < start + 3 && index < labels.length;
                  index++
                ) ...[
                  if (index > start) const SizedBox(height: 6),
                  labels[index],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}
