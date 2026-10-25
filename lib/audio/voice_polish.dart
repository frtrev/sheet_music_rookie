import 'dart:math' as math;
import 'dart:typed_data';

/// Offline playback treatment; never used by pitch detection or scoring.
/// Zero is an exact bypass. Processing preserves the dry signal's timing.
class VoicePolish {
  const VoicePolish();

  Float64List process(
    Float64List input, {
    required int sampleRate,
    required double amount,
  }) {
    if (sampleRate < 1000) throw ArgumentError.value(sampleRate, 'sampleRate');
    final mix = amount.isFinite ? amount.clamp(0.0, 1.0) : 0.0;
    if (mix == 0 || input.isEmpty) return Float64List.fromList(input);
    final tail = (sampleRate * .28).round();
    final output = Float64List(input.length + tail);
    final dry = Float64List(input.length);
    var previous = 0.0;
    var highPass = 0.0;
    var warmth = 0.0;
    var smooth = 0.0;
    var envelope = 0.0;
    var gain = 1.0;
    var peak = 0.0;
    final hp = math.exp(-2 * math.pi * 65 / sampleRate);
    final low = 1 - math.exp(-2 * math.pi * 350 / sampleRate);
    final air = 1 - math.exp(-2 * math.pi * 6500 / sampleRate);
    final attack = math.exp(-1 / (sampleRate * .008));
    final release = math.exp(-1 / (sampleRate * .12));
    for (var i = 0; i < input.length; i++) {
      final x = input[i].isFinite ? input[i] : 0.0;
      dry[i] = x;
      highPass = hp * (highPass + x - previous);
      previous = x;
      warmth += low * (highPass - warmth);
      smooth += air * (highPass - smooth);
      final shaped = smooth + .16 * (smooth - warmth);
      final magnitude = shaped.abs();
      final coefficient = magnitude > envelope ? attack : release;
      envelope = coefficient * envelope + (1 - coefficient) * magnitude;
      // Gentle downward expansion only at quiet levels; avoid hard gating.
      final cleanup = .35 + .65 * (envelope / .008).clamp(0.0, 1.0);
      const threshold = .18;
      final targetGain = envelope > threshold
          ? math.pow(threshold / envelope, .6).toDouble()
          : 1.0;
      final gainCoefficient = targetGain < gain ? attack : release;
      gain = gainCoefficient * gain + (1 - gainCoefficient) * targetGain;
      output[i] = shaped * cleanup * gain * 1.18;
      peak = math.max(peak, output[i].abs());
    }
    // No automatic amplification of silence or very quiet room noise.
    final headroom = peak > .85 ? .85 / peak : 1.0;
    final delays = [
      (.029 * sampleRate).round(),
      (.047 * sampleRate).round(),
      (.079 * sampleRate).round(),
    ];
    final room = Float64List(output.length);
    for (var i = 0; i < output.length; i++) {
      var ambience = 0.0;
      for (final delay in delays) {
        if (i >= delay) ambience += room[i - delay] * .16;
      }
      room[i] = output[i] * headroom + ambience;
      final wet = output[i] * headroom + ambience * .24;
      final original = i < dry.length ? dry[i] : 0.0;
      output[i] = original * (1 - mix) + wet * mix;
    }
    // Smooth the last few milliseconds of the room tail.
    final fade = (sampleRate * .01).round();
    for (var i = 0; i < fade; i++) {
      output[output.length - 1 - i] *= i / fade;
    }
    return output;
  }
}
