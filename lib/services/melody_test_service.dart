import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/microphone_service.dart';
import '../models/composition.dart';
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
/// that overlays the original voice with the same piano reference used by
/// normal score playback.
class MelodyTestSession {
  MelodyTestSession(
    this.composition, {
    this.outputSampleRate = 24000,
  }) : _expected = _expectedSpans(composition),
       _startsWithRest = _scoreStartsWithRest(composition),
       _scoreEndTick = _scoreDurationTicks(composition);

  final Composition composition;
  final int outputSampleRate;
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
    final milliseconds = cursorTick == null
        ? 0
        : (cursorTick * 60000 / (composition.tempoBpm * 480)).round();
    return _pitchAt(milliseconds);
  }

  int? get currentCursorTick {
    if (_attemptStartMs == null || _lastFrameMs == null) return null;
    final elapsedMs = math.max(0, _lastFrameMs! - _attemptStartMs!);
    return (elapsedMs * composition.tempoBpm * 480 / 60000)
        .round()
        .clamp(0, _scoreEndTick)
        .toInt();
  }

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
    return timelineStarted && currentCursorTick == _scoreEndTick;
  }

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
    const insertMs = 0;
    final voiceDurationMs = math.max(0, sourceEndMs - sourceStartMs);
    final outputLength = math.max(
      referenceSamples.length,
      ((insertMs + voiceDurationMs) * outputSampleRate / 1000).ceil(),
    );
    final mixed = Float64List(outputLength);
    for (var index = 0; index < referenceSamples.length; index++) {
      mixed[index] = referenceSamples[index] * .72;
    }

    final insertSample = (insertMs * outputSampleRate / 1000).round();
    final voiceSamples = (voiceDurationMs * outputSampleRate / 1000).round();
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
      mixed[insertSample + index] += voice * 1.15;
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
