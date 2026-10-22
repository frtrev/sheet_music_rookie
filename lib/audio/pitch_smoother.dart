import '../models/pitch_detection_result.dart';

class PitchSmoother {
  final List<PitchDetectionResult> _history = [];

  PitchDetectionResult add(PitchDetectionResult result, int windowSize) {
    _history.add(result);
    while (_history.length > windowSize) {
      _history.removeAt(0);
    }
    final frequencies = _history.map((item) => item.frequencyHz).toList()
      ..sort();
    final median = frequencies[frequencies.length ~/ 2];
    final closest = _history.reduce(
      (a, b) => (a.frequencyHz - median).abs() < (b.frequencyHz - median).abs()
          ? a
          : b,
    );
    return PitchDetectionResult(
      timestampMs: result.timestampMs,
      frequencyHz: median,
      midiNote: closest.midiNote,
      noteName: closest.noteName,
      octave: closest.octave,
      centsDeviation: closest.centsDeviation,
      confidence:
          _history.map((item) => item.confidence).reduce((a, b) => a + b) /
          _history.length,
      rmsAmplitude: result.rmsAmplitude,
    );
  }

  void clear() => _history.clear();
}
