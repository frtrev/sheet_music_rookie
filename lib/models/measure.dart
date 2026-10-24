import 'musical_note.dart';

class Measure {
  const Measure({
    required this.index,
    this.notes = const [],
    this.beatsPerMeasure,
    this.beatUnit,
  });

  final int index;
  final List<MusicalNote> notes;
  final int? beatsPerMeasure;
  final int? beatUnit;

  int effectiveBeats(int fallback) => beatsPerMeasure ?? fallback;

  int effectiveBeatUnit(int fallback) => beatUnit ?? fallback;

  int capacityTicks(int fallbackBeats, int fallbackBeatUnit) =>
      effectiveBeats(fallbackBeats) *
      1920 ~/
      effectiveBeatUnit(fallbackBeatUnit);
}
