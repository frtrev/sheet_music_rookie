import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/pitch_detection_result.dart';
import 'package:sheet_music_rookie/widgets/practice_pitch_gauge.dart';

PitchDetectionResult pitchAt(double frequencyHz) => PitchDetectionResult(
  timestampMs: 0,
  frequencyHz: frequencyHz,
  midiNote: 69,
  noteName: 'A',
  octave: 4,
  centsDeviation: 0,
  confidence: 1,
  rmsAmplitude: .2,
);

void main() {
  test('pitch gauge centers and turns green on the target frequency', () {
    final reading = PitchGaugeReading.from(
      detectedPitch: pitchAt(440),
      targetMidiPitch: 69,
    );

    expect(reading, isNotNull);
    expect(reading!.errorCents, closeTo(0, .001));
    expect(reading.position, 0);
    expect(reading.description, 'on pitch');
    expect(reading.color.g, greaterThan(reading.color.r));
  });

  test('pitch gauge moves up for sharp and down for flat tones', () {
    final sharp = PitchGaugeReading.from(
      detectedPitch: pitchAt((440 * math.pow(2, 1 / 12)).toDouble()),
      targetMidiPitch: 69,
    )!;
    final flat = PitchGaugeReading.from(
      detectedPitch: pitchAt((440 * math.pow(2, -1 / 12)).toDouble()),
      targetMidiPitch: 69,
    )!;

    expect(sharp.errorCents, closeTo(100, .001));
    expect(sharp.position, closeTo(.5, .001));
    expect(sharp.description, '100 cents sharp');
    expect(flat.errorCents, closeTo(-100, .001));
    expect(flat.position, closeTo(-.5, .001));
    expect(flat.description, '100 cents flat');
    expect(sharp.color.r, greaterThan(sharp.color.g));
    expect(flat.color.r, greaterThan(flat.color.g));
  });

  test('pitch gauge clamps tones beyond its two-semitone range', () {
    final reading = PitchGaugeReading.from(
      detectedPitch: pitchAt(880),
      targetMidiPitch: 69,
    )!;

    expect(reading.position, 1);
  });
}
