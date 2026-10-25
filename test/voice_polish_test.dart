import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/voice_polish.dart';

void main() {
  const processor = VoicePolish();
  test('off is an exact bypass and does not alter the source', () {
    final source = Float64List.fromList([0, .2, -.4, .8, 0]);
    final output = processor.process(source, sampleRate: 24000, amount: 0);
    expect(output, orderedEquals(source));
    expect(identical(output, source), isFalse);
  });
  test('silence stays silent at every strength', () {
    for (final amount in [.35, 1.0]) {
      expect(
        processor
            .process(Float64List(2400), sampleRate: 24000, amount: amount)
            .every((v) => v == 0),
        isTrue,
      );
    }
  });
  test(
    'removes DC rumble and decays the ambience without moving the onset',
    () {
      final source = Float64List(24000)..[0] = .7;
      final output = processor.process(source, sampleRate: 24000, amount: 1);
      expect(output.first.abs(), greaterThan(0));
      expect(output.length, greaterThan(source.length));
      expect(output.last, 0);
      expect(output.every((v) => v.isFinite && v.abs() <= 1), isTrue);
      final dc = processor.process(
        Float64List.fromList(List.filled(24000, .3)),
        sampleRate: 24000,
        amount: 1,
      );
      expect(dc[23000].abs(), lessThan(.001));
    },
  );
  test('strength gives a gradual wet/dry blend with stable output', () {
    final source = Float64List.fromList(
      List.generate(24000, (i) => .3 * math.sin(2 * math.pi * 440 * i / 24000)),
    );
    final half = processor.process(source, sampleRate: 24000, amount: .5);
    final full = processor.process(source, sampleRate: 24000, amount: 1);
    for (var i = 0; i < source.length; i += 239) {
      expect(half[i], closeTo((source[i] + full[i]) / 2, 1e-9));
    }
    expect(source[0], 0);
  });
}
