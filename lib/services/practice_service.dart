import 'dart:math' as math;

import '../models/composition.dart';
import '../music/performance_plan.dart';
import '../models/pitch_detection_result.dart';
import '../models/voice_detection_settings.dart';
import 'score_playback_service.dart';

class PracticeTarget {
  const PracticeTarget({
    required this.startTick,
    required this.durationTicks,
    required this.soundingMidiPitch,
    required this.sourceEventIndex,
    this.silenceBeforeTicks = 0,
  });

  final int startTick;
  final int durationTicks;
  final int soundingMidiPitch;
  final int sourceEventIndex;
  final int silenceBeforeTicks;

  int get endTick => startTick + durationTicks;

  PracticeTarget extendBy(int ticks) => PracticeTarget(
    startTick: startTick,
    durationTicks: durationTicks + ticks,
    soundingMidiPitch: soundingMidiPitch,
    sourceEventIndex: sourceEventIndex,
    silenceBeforeTicks: silenceBeforeTicks,
  );
}

class PracticeUpdate {
  const PracticeUpdate({required this.cursorTick, required this.completed});
  final int cursorTick;
  final bool completed;
}

/// Advances through a monophonic score when the expected sounding pitch has
/// been held long enough. It intentionally does not own microphone or UI state.
class PracticeSession {
  factory PracticeSession(
    Composition source, {
    required int pitchStabilityMs,
    double pitchToleranceCents = 45,
    int articulationGapMs = 35,
    PracticeDifficulty difficulty = PracticeDifficulty.beginner,
    double requiredDurationFraction = .6,
  }) => PracticeSession._(
    PerformancePlan(source),
    pitchStabilityMs: pitchStabilityMs,
    pitchToleranceCents: pitchToleranceCents,
    articulationGapMs: articulationGapMs,
    difficulty: difficulty,
    requiredDurationFraction: requiredDurationFraction,
  );

  PracticeSession._(
    this.plan, {
    required this.pitchStabilityMs,
    required this.pitchToleranceCents,
    required this.articulationGapMs,
    required this.difficulty,
    required this.requiredDurationFraction,
  }) : composition = plan.expanded,
       targets = _targetsFor(plan.expanded);

  final Composition composition;
  final PerformancePlan plan;
  int sourceTickAt(int tick) => plan.sourceTickAt(tick);
  final int pitchStabilityMs;
  double pitchToleranceCents;
  int articulationGapMs;
  PracticeDifficulty difficulty;
  final double requiredDurationFraction;
  final List<PracticeTarget> targets;
  int _targetIndex = 0;
  int? _correctPitchSinceMs;
  int _heldMs = 0;
  int _streakBaseMs = 0;
  double _progress = 0;
  bool _awaitingRelease = false;
  bool _releaseRequiresRest = false;
  int _requiredReleaseMs = 0;
  int? _silenceStartedMs;
  int? _previousTargetPitch;

  bool get hasTargets => targets.isNotEmpty;
  bool get completed => _targetIndex >= targets.length;
  PracticeTarget? get currentTarget => completed ? null : targets[_targetIndex];
  double get progress => _progress;

  PracticeUpdate? process(
    PitchDetectionResult? result, {
    required bool voiceDetected,
    int? timestampMs,
  }) {
    final target = currentTarget;
    if (target == null) return null;
    final frameTimestamp = timestampMs ?? result?.timestampMs;
    if (_awaitingRelease) {
      if (!voiceDetected) {
        if (frameTimestamp == null) return null;
        _silenceStartedMs ??= frameTimestamp;
        if (frameTimestamp - _silenceStartedMs! < _requiredReleaseMs) {
          return null;
        }
        _clearReleaseGate();
        return PracticeUpdate(cursorTick: target.startTick, completed: false);
      }
      _silenceStartedMs = null;
      final changedToExpectedPitch =
          !_releaseRequiresRest &&
          result != null &&
          target.soundingMidiPitch != _previousTargetPitch &&
          _isPitchAccepted(result, target);
      if (!changedToExpectedPitch) return null;
      _clearReleaseGate();
    }
    if (!voiceDetected || result == null || !_isPitchAccepted(result, target)) {
      return _handleMiss();
    }

    if (_correctPitchSinceMs == null) {
      _correctPitchSinceMs = result.timestampMs;
      _streakBaseMs = _heldMs;
    }
    _heldMs = _streakBaseMs + result.timestampMs - _correctPitchSinceMs!;
    final noteDurationMs =
        target.durationTicks * 60000 / (composition.tempoBpm * 480);
    final requiredMs = math.max(
      pitchStabilityMs,
      (noteDurationMs * requiredDurationFraction).round(),
    );
    _progress = (_heldMs / requiredMs).clamp(0.0, 1.0).toDouble();
    if (_heldMs < requiredMs) return null;

    final completedTarget = target;
    _targetIndex++;
    _resetCurrentNote();
    if (!completed) {
      final nextTarget = targets[_targetIndex];
      _releaseRequiresRest = nextTarget.silenceBeforeTicks > 0;
      _requiredReleaseMs = _releaseRequiresRest
          ? (nextTarget.silenceBeforeTicks *
                    60000 /
                    (composition.tempoBpm * 480))
                .round()
          : articulationGapMs;
      _previousTargetPitch = completedTarget.soundingMidiPitch;
      _awaitingRelease = _requiredReleaseMs > 0;
      _silenceStartedMs = null;
    }
    return PracticeUpdate(
      cursorTick: completed
          ? _scoreEndTick(composition)
          : _releaseRequiresRest
          ? completedTarget.endTick
          : targets[_targetIndex].startTick,
      completed: completed,
    );
  }

  PracticeUpdate? _handleMiss() {
    switch (difficulty) {
      case PracticeDifficulty.beginner:
        _correctPitchSinceMs = null;
        _streakBaseMs = _heldMs;
        return null;
      case PracticeDifficulty.medium:
        _resetCurrentNote();
        return null;
      case PracticeDifficulty.advanced:
        final shouldMove = _targetIndex != 0 || _heldMs != 0 || _progress != 0;
        _targetIndex = 0;
        _resetCurrentNote();
        _clearReleaseGate();
        if (!shouldMove || targets.isEmpty) return null;
        return PracticeUpdate(
          cursorTick: targets.first.startTick,
          completed: false,
        );
    }
  }

  void _resetCurrentNote() {
    _correctPitchSinceMs = null;
    _heldMs = 0;
    _streakBaseMs = 0;
    _progress = 0;
  }

  void _clearReleaseGate() {
    _awaitingRelease = false;
    _releaseRequiresRest = false;
    _requiredReleaseMs = 0;
    _silenceStartedMs = null;
    _previousTargetPitch = null;
  }

  bool _isPitchAccepted(PitchDetectionResult result, PracticeTarget target) {
    if (result.frequencyHz <= 0) return false;
    final targetHz = 440 * math.pow(2, (target.soundingMidiPitch - 69) / 12);
    final errorCents =
        1200 * math.log(result.frequencyHz / targetHz) / math.ln2;
    return errorCents.abs() <= pitchToleranceCents;
  }

  static List<PracticeTarget> _targetsFor(Composition composition) {
    final targets = <PracticeTarget>[];
    for (final measure in composition.measures) {
      for (final note in measure.notes) {
        if (note.isRest) continue;
        final startTick =
            composition.measureStartTick(measure.index) + note.startTick;
        final soundingPitch = playbackMidiPitch(
          composition,
          note.midiPitch,
          accidental: note.accidental,
        );
        final continuesSource =
            targets.isNotEmpty &&
            note.sourceEventIndex >= 0 &&
            targets.last.sourceEventIndex == note.sourceEventIndex &&
            targets.last.endTick == startTick;
        final continuesTie =
            targets.isNotEmpty &&
            note.tieFromPrevious &&
            targets.last.soundingMidiPitch == soundingPitch &&
            targets.last.endTick == startTick;
        if (continuesSource || continuesTie) {
          targets[targets.length - 1] = targets.last.extendBy(
            note.durationTicks,
          );
          continue;
        }
        targets.add(
          PracticeTarget(
            startTick: startTick,
            durationTicks: note.durationTicks,
            soundingMidiPitch: soundingPitch,
            sourceEventIndex: note.sourceEventIndex,
            silenceBeforeTicks: targets.isEmpty
                ? 0
                : math.max(0, startTick - targets.last.endTick).toInt(),
          ),
        );
      }
    }
    return targets;
  }

  static int _scoreEndTick(Composition composition) {
    var end = 0;
    for (final measure in composition.measures) {
      for (final note in measure.notes) {
        end = math.max(
          end,
          composition.measureStartTick(measure.index) +
              note.startTick +
              note.durationTicks,
        );
      }
    }
    return end;
  }
}
