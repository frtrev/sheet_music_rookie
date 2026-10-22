import '../models/musical_note.dart';

class RhythmQuantizer {
  const RhythmQuantizer();

  int quantizeDuration(int durationMs, int tempoBpm) {
    final ticks = (durationMs * 480 * tempoBpm / 60000).round();
    return NoteValue.values
        .map((value) => value.ticks)
        .reduce((a, b) => (a - ticks).abs() <= (b - ticks).abs() ? a : b);
  }
}
