import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/pitch_detector.dart';
import 'package:sheet_music_rookie/models/voice_detection_settings.dart';

void main() {
  test('YIN detects an A4 fundamental near 440 Hz', () {
    const sampleRate = 44100;
    final samples = Float64List.fromList(
      List.generate(
        4096,
        (index) => .6 * math.sin(2 * math.pi * 440 * index / sampleRate),
      ),
    );

    final result = const PitchDetector(sampleRate: sampleRate)
        .analyze(samples, 100, const VoiceDetectionSettings());

    expect(result, isNotNull);
    expect(result!.frequencyHz, closeTo(440, 1));
    expect(result.midiNote, 69);
    expect(result.noteName, 'A');
    expect(result.octave, 4);
    expect(result.confidence, greaterThan(.9));
  });
}
