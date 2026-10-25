import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../audio/microphone_service.dart';
import '../audio/voice_polish.dart';
import '../models/composition.dart';
import '../music/performance_plan.dart';
import '../models/pitch_detection_result.dart';
import 'score_playback_service.dart';

class MelodyTestResult {
  const MelodyTestResult({
    required this.score,
    required this.pitchScore,
    required this.timingScore,
    required this.matchupWave,
  });

  final int score;
  final int pitchScore;
  final int timingScore;
  final Uint8List? matchupWave;
}

/// Captures one sung attempt, compares it with the score, and creates a WAV
/// that overlays the optionally polished voice with the same piano reference used by
/// normal score playback.
class MelodyTestSession {
  factory MelodyTestSession(
    Composition source, {
    int outputSampleRate = 24000,
    double voicePolish = 0,
  }) => MelodyTestSession._(
    PerformancePlan(source),
    outputSampleRate: outputSampleRate,
    voicePolish: voicePolish,
  );

  MelodyTestSession._(
    this.plan, {
    required this.outputSampleRate,
    required this.voicePolish,
  }) : composition = plan.expanded,
       _expected = _expectedSpans(plan.expanded),
       _startsWithRest = _scoreStartsWithRest(plan.expanded),
       _scoreEndTick = _scoreDurationTicks(plan.expanded);

  final Composition composition;
  final PerformancePlan plan;
  final int outputSampleRate;
  final double voicePolish;
  final List<_ExpectedSpan> _expected;
  final bool _startsWithRest;
  final int _scoreEndTick;
  final List<_AttemptFrame> _attemptFrames = [];
  final List<double> _audioSamples = [];
  int? _attemptStartMs;
  int? _firstVoiceMs;
  int? _lastVoiceMs;
  int? _lastFrameMs;
  bool _hasAudioFrame = false;

  bool get hasNotes => _expected.isNotEmpty;
  bool get hasVoice => _firstVoiceMs != null;
  bool get timelineStarted => _attemptStartMs != null;

  int? get currentExpectedMidiPitch {
    final cursorTick = currentCursorTick;
    return expectedMidiPitchAtTick(cursorTick ?? 0);
  }

  int? expectedMidiPitchAtTick(int cursorTick) => _pitchAt(
    (plan.performanceTickAt(cursorTick) * 60000 / (composition.tempoBpm * 480))
        .round(),
  );

  int _performanceTickAt(Duration elapsed) =>
      (elapsed.inMicroseconds * composition.tempoBpm * 480 / 60000000)
          .round()
          .clamp(0, _scoreEndTick)
          .toInt();

  int cursorTickAt(Duration elapsed) =>
      plan.sourceTickAt(_performanceTickAt(elapsed));

  bool hasReachedEnd(Duration elapsed) =>
      _performanceTickAt(elapsed) >= _scoreEndTick;

  int? get _currentPerformanceTick {
    if (_attemptStartMs == null || _lastFrameMs == null) return null;
    final elapsedMs = math.max(0, _lastFrameMs! - _attemptStartMs!);
    return _performanceTickAt(Duration(milliseconds: elapsedMs));
  }

  int? get currentCursorTick => _currentPerformanceTick == null
      ? null
      : plan.sourceTickAt(_currentPerformanceTick!);

  bool addFrame(
    AudioFrame frame, {
    required PitchDetectionResult? pitch,
    required bool voiceDetected,
  }) {
    _appendAudio(frame.samples);
    _lastFrameMs = frame.timestampMs;
    final detectedVoice = voiceDetected && pitch != null;
    if (_attemptStartMs == null && (_startsWithRest || detectedVoice)) {
      _attemptStartMs = frame.timestampMs;
    }
    if (detectedVoice) {
      _firstVoiceMs ??= frame.timestampMs;
      _lastVoiceMs = frame.timestampMs;
    }
    _attemptFrames.add(
      _AttemptFrame(
        timestampMs: frame.timestampMs,
        frequencyHz: detectedVoice ? pitch!.frequencyHz : null,
        voiceDetected: detectedVoice,
      ),
    );
    return timelineStarted && _currentPerformanceTick == _scoreEndTick;
  }

  Future<MelodyTestResult> finishAsync() => compute(_finishSession, this);

  MelodyTestResult finish() {
    if (_attemptStartMs == null ||
        _firstVoiceMs == null ||
        _lastVoiceMs == null ||
        _expected.isEmpty) {
      return const MelodyTestResult(
        score: 0,
        pitchScore: 0,
        timingScore: 0,
        matchupWave: null,
      );
    }
    final scores = _calculateScores();
    return MelodyTestResult(
      score: (scores.pitch * .75 + scores.timing * .25).round().clamp(0, 100),
      pitchScore: scores.pitch.round().clamp(0, 100),
      timingScore: scores.timing.round().clamp(0, 100),
      matchupWave: _renderMatchup(),
    );
  }

  void _appendAudio(Float64List samples) {
    if (!_hasAudioFrame) {
      _audioSamples.addAll(samples);
      _hasAudioFrame = true;
      return;
    }
    final overlapStart = math.max(
      0,
      samples.length - MicrophoneService.hopSize,
    );
    _audioSamples.addAll(samples.sublist(overlapStart));
  }

  ({double pitch, double timing}) _calculateScores() {
    final attemptStartMs = _attemptStartMs!;
    final expectedDurationMs = math.max(
      1,
      (_scoreEndTick * 60000 / (composition.tempoBpm * 480)).round(),
    );
    const stepMs = 20;
    var frameIndex = 0;
    var pitchTotal = 0.0;
    var pitchFrames = 0;
    var timingEarned = 0.0;
    var timingPossible = 0.0;

    for (
      var elapsedMs = 0;
      elapsedMs < expectedDurationMs;
      elapsedMs += stepMs
    ) {
      final expectedPitch = _pitchAt(elapsedMs);
      final recordingMs = attemptStartMs + elapsedMs;
      while (frameIndex + 1 < _attemptFrames.length &&
          (_attemptFrames[frameIndex + 1].timestampMs - recordingMs).abs() <=
              (_attemptFrames[frameIndex].timestampMs - recordingMs).abs()) {
        frameIndex++;
      }
      final frame = _attemptFrames[frameIndex];
      final closeEnough = (frame.timestampMs - recordingMs).abs() <= 80;
      final actualVoice = closeEnough && frame.voiceDetected;
      final expectedVoice = expectedPitch != null;
      final timingWeight = expectedVoice ? 1.0 : .35;
      timingPossible += timingWeight;
      if (actualVoice == expectedVoice) timingEarned += timingWeight;

      if (expectedPitch != null) {
        pitchFrames++;
        final frequency = actualVoice ? frame.frequencyHz : null;
        if (frequency != null && frequency > 0) {
          final targetHz = 440 * math.pow(2, (expectedPitch - 69) / 12);
          final cents = (1200 * math.log(frequency / targetHz) / math.ln2)
              .abs();
          pitchTotal += cents <= 25
              ? 1
              : (1 - (cents - 25) / 175).clamp(0.0, 1.0);
        }
      }
    }

    final actualDurationMs = math.max(1, _lastVoiceMs! - attemptStartMs);
    final durationScore =
        math.min(actualDurationMs, expectedDurationMs) /
        math.max(actualDurationMs, expectedDurationMs);
    final pitchScore = pitchFrames == 0 ? 0.0 : pitchTotal / pitchFrames * 100;
    final frameTimingScore = timingPossible == 0
        ? 0.0
        : timingEarned / timingPossible;
    final timingScore = (frameTimingScore * .7 + durationScore * .3) * 100;
    return (pitch: pitchScore, timing: timingScore);
  }

  int? _pitchAt(int milliseconds) {
    for (final span in _expected) {
      if (milliseconds >= span.startMs && milliseconds < span.endMs) {
        return span.midiPitch;
      }
    }
    return null;
  }

  Uint8List? _renderMatchup() {
    final reference = PianoWaveSynthesizer(sampleRate: outputSampleRate)
        .render(composition);
    if (reference == null || _audioSamples.isEmpty) return reference;
    final referenceSamples = _decodeWave(reference);
    final sourceStartMs = _attemptStartMs!;
    final sourceEndMs = math.min(
      (_audioSamples.length * 1000 / MicrophoneService.sampleRate).round(),
      _lastVoiceMs! + 300,
    );
    final voiceDurationMs = math.max(0, sourceEndMs - sourceStartMs);
    final voiceSamples = (voiceDurationMs * outputSampleRate / 1000).round();
    final capturedVoice = Float64List(voiceSamples);
    for (var index = 0; index < voiceSamples; index++) {
      final sourcePosition =
          (sourceStartMs / 1000 + index / outputSampleRate) *
          MicrophoneService.sampleRate;
      final lower = sourcePosition.floor();
      if (lower < 0 || lower >= _audioSamples.length) continue;
      final upper = math.min(lower + 1, _audioSamples.length - 1);
      final fraction = sourcePosition - lower;
      final voice =
          _audioSamples[lower] * (1 - fraction) +
          _audioSamples[upper] * fraction;
      capturedVoice[index] = voice;
    }
    final polished = const VoicePolish().process(
      capturedVoice,
      sampleRate: outputSampleRate,
      amount: voicePolish,
    );
    final mixed = Float64List(
      math.max(referenceSamples.length, polished.length),
    );
    for (var i = 0; i < referenceSamples.length; i++) {
      mixed[i] = referenceSamples[i] * .72;
    }
    for (var i = 0; i < polished.length; i++) {
      mixed[i] += polished[i] * 1.15;
    }
    // Keep the final voice + piano mix below clipping when polish is enabled.
    if (voicePolish > 0) {
      var peak = 0.0;
      for (final sample in mixed) {
        peak = math.max(peak, sample.abs());
      }
      if (peak > .97) {
        for (var i = 0; i < mixed.length; i++) {
          mixed[i] *= .97 / peak;
        }
      }
    }
    return _encodeWave(mixed, outputSampleRate);
  }

  static List<_ExpectedSpan> _expectedSpans(Composition composition) {
    final spans = <_ExpectedSpan>[];
    final msPerTick = 60000 / composition.tempoBpm / 480;
    for (final measure in composition.measures) {
      final measureStart = composition.measureStartTick(measure.index);
      for (final note in measure.notes) {
        if (note.isRest) continue;
        final startTick = measureStart + note.startTick;
        spans.add(
          _ExpectedSpan(
            startMs: (startTick * msPerTick).round(),
            endMs: ((startTick + note.durationTicks) * msPerTick).round(),
            midiPitch: playbackMidiPitch(
              composition,
              note.midiPitch,
              accidental: note.accidental,
            ),
          ),
        );
      }
    }
    spans.sort((a, b) => a.startMs.compareTo(b.startMs));
    return spans;
  }

  static bool _scoreStartsWithRest(Composition composition) {
    ({int startTick, bool isRest})? firstEvent;
    for (final measure in composition.measures) {
      final measureStart = composition.measureStartTick(measure.index);
      for (final note in measure.notes) {
        final startTick = measureStart + note.startTick;
        if (firstEvent == null || startTick < firstEvent.startTick) {
          firstEvent = (startTick: startTick, isRest: note.isRest);
        }
      }
    }
    return firstEvent == null || firstEvent.startTick > 0 || firstEvent.isRest;
  }

  static int _scoreDurationTicks(Composition composition) {
    var result = 0;
    for (final measure in composition.measures) {
      final measureStart = composition.measureStartTick(measure.index);
      for (final note in measure.notes) {
        result = math.max(
          result,
          measureStart + note.startTick + note.durationTicks,
        );
      }
    }
    return result;
  }
}

class _AttemptFrame {
  const _AttemptFrame({
    required this.timestampMs,
    required this.frequencyHz,
    required this.voiceDetected,
  });

  final int timestampMs;
  final double? frequencyHz;
  final bool voiceDetected;
}

class _ExpectedSpan {
  const _ExpectedSpan({
    required this.startMs,
    required this.endMs,
    required this.midiPitch,
  });

  final int startMs;
  final int endMs;
  final int midiPitch;
}

Float64List _decodeWave(Uint8List wave) {
  if (wave.length <= 44) return Float64List(0);
  final data = ByteData.sublistView(wave);
  final samples = Float64List((wave.length - 44) ~/ 2);
  for (var index = 0; index < samples.length; index++) {
    samples[index] = data.getInt16(44 + index * 2, Endian.little) / 32768;
  }
  return samples;
}

Uint8List _encodeWave(Float64List samples, int sampleRate) {
  final result = Uint8List(44 + samples.length * 2);
  final bytes = ByteData.sublistView(result);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, result.length - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    bytes.setInt16(
      44 + index * 2,
      (samples[index].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return result;
}

MelodyTestResult _finishSession(MelodyTestSession session) => session.finish();
