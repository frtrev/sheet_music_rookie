import 'dart:math' as math;
import 'dart:typed_data';

import '../models/pitch_detection_result.dart';
import '../models/voice_detection_settings.dart';

/// YIN fundamental-frequency detector. Unlike a largest-FFT-bin approach, YIN
/// compares waveform periods and is resilient when vocal harmonics are louder
/// than the fundamental.
class PitchDetector {
  const PitchDetector({this.sampleRate = 44100});

  final int sampleRate;

  PitchDetectionResult? analyze(
    Float64List samples,
    int timestampMs,
    VoiceDetectionSettings settings,
  ) {
    var squareSum = 0.0;
    for (final sample in samples) {
      squareSum += sample * sample;
    }
    final rms = math.sqrt(squareSum / samples.length);
    final minLag = (sampleRate / settings.maximumFrequency).floor().clamp(
      2,
      samples.length ~/ 2,
    );
    final maxLag = (sampleRate / settings.minimumFrequency).ceil().clamp(
      minLag + 1,
      samples.length ~/ 2,
    );
    final difference = Float64List(maxLag + 1);

    final comparisonLength = samples.length - maxLag;
    for (var lag = 1; lag <= maxLag; lag++) {
      var sum = 0.0;
      for (var index = 0; index < comparisonLength; index++) {
        final delta = samples[index] - samples[index + lag];
        sum += delta * delta;
      }
      difference[lag] = sum;
    }

    var runningSum = 0.0;
    difference[0] = 1;
    for (var lag = 1; lag <= maxLag; lag++) {
      runningSum += difference[lag];
      difference[lag] = runningSum == 0
          ? 1
          : difference[lag] * lag / runningSum;
    }

    var bestLag = -1;
    const yinThreshold = 0.15;
    for (var lag = minLag; lag < maxLag; lag++) {
      if (difference[lag] < yinThreshold) {
        while (lag + 1 <= maxLag && difference[lag + 1] < difference[lag]) {
          lag++;
        }
        bestLag = lag;
        break;
      }
    }
    if (bestLag < 0) {
      var minimum = 1.0;
      for (var lag = minLag; lag <= maxLag; lag++) {
        if (difference[lag] < minimum) {
          minimum = difference[lag];
          bestLag = lag;
        }
      }
      if (minimum > 0.35) return null;
    }

    final refinedLag = _parabolicLag(difference, bestLag, maxLag);
    final frequency = sampleRate / refinedLag;
    if (frequency < settings.minimumFrequency ||
        frequency > settings.maximumFrequency) {
      return null;
    }
    final preciseMidi = 69 + 12 * math.log(frequency / 440) / math.ln2;
    final midi = preciseMidi.round();
    const names = [
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
    return PitchDetectionResult(
      timestampMs: timestampMs,
      frequencyHz: frequency,
      midiNote: midi,
      noteName: names[midi % 12],
      octave: midi ~/ 12 - 1,
      centsDeviation: (preciseMidi - midi) * 100,
      confidence: (1 - difference[bestLag]).clamp(0, 1),
      rmsAmplitude: rms,
    );
  }

  double _parabolicLag(Float64List values, int lag, int maxLag) {
    if (lag <= 1 || lag >= maxLag) return lag.toDouble();
    final left = values[lag - 1];
    final center = values[lag];
    final right = values[lag + 1];
    final denominator = 2 * (2 * center - right - left);
    return denominator.abs() < 0.000001
        ? lag.toDouble()
        : lag + (right - left) / denominator;
  }
}
