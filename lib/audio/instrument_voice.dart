import 'dart:math' as math;

import '../models/playback_instrument.dart';

/// Lightweight modeled instruments. Upper partials are band-limited and decay
/// independently, avoiding the static, metallic spectrum of the old voice.
class InstrumentVoice {
  InstrumentVoice(this.instrument, this.frequency, int sampleRate) {
    final weights = switch (instrument) {
      PlaybackInstrument.nylonGuitar => [1.0, .27, .12, .065, .035, .02],
      PlaybackInstrument.flute => [1.0, .09, .025],
      PlaybackInstrument.organ => [1.0, .35, .16, .075],
      _ => [1.0, .3, .14, .065, .035, .018, .009, .005],
    };
    for (var i = 0; i < weights.length; i++) {
      final harmonic = i + 1;
      final ratio = instrument == PlaybackInstrument.piano
          ? harmonic * math.sqrt(1 + .00004 * harmonic * harmonic)
          : harmonic.toDouble();
      if (frequency * ratio < sampleRate * .45) {
        partials.add((
          ratio: ratio,
          weight: weights[i],
          decay: switch (instrument) {
            PlaybackInstrument.piano => .8 + i * .8,
            PlaybackInstrument.nylonGuitar => 1.6 + i * 1.1,
            _ => 0.0,
          },
        ));
      }
    }
  }
  final PlaybackInstrument instrument;
  final double frequency;
  final partials = <({double ratio, double weight, double decay})>[];

  double sample(double time, double remaining) {
    final attackSeconds = switch (instrument) {
      PlaybackInstrument.flute => .035,
      PlaybackInstrument.organ => .018,
      _ => .006,
    };
    final attack = (time / attackSeconds).clamp(0.0, 1.0);
    final release = (remaining / .065).clamp(0.0, 1.0);
    var signal = 0.0;
    final vibrato = instrument == PlaybackInstrument.flute
        ? .0012 * math.sin(2 * math.pi * 5 * time) * math.min(1, time / .2)
        : 0.0;
    final phase = 2 * math.pi * frequency * time + vibrato;
    for (final p in partials) {
      signal +=
          p.weight * math.sin(phase * p.ratio) * math.exp(-p.decay * time);
    }
    return .36 * attack * release * signal;
  }
}
