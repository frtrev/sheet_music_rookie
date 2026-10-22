import 'dart:math' as math;

class PitchDetectionResult {
  const PitchDetectionResult({
    required this.timestampMs,
    required this.frequencyHz,
    required this.midiNote,
    required this.noteName,
    required this.octave,
    required this.centsDeviation,
    required this.confidence,
    required this.rmsAmplitude,
  });

  final int timestampMs;
  final double frequencyHz;
  final int midiNote;
  final String noteName;
  final int octave;
  final double centsDeviation;
  final double confidence;
  final double rmsAmplitude;

  double get dbfs => rmsAmplitude <= 0
      ? -120
      : 20 * math.log(rmsAmplitude.clamp(0.000001, 1)) / math.ln10;
}
