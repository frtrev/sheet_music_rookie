import 'musical_note.dart';

class Measure {
  const Measure({
    required this.index,
    this.notes = const [],
    this.beatsPerMeasure,
    this.beatUnit,
    this.barlines = const [],
  });

  final int index;
  final List<MusicalNote> notes;
  final int? beatsPerMeasure;
  final int? beatUnit;

  /// Original MusicXML barlines, including repeat and numbered-ending marks.
  final List<String> barlines;

  int effectiveBeats(int fallback) => beatsPerMeasure ?? fallback;

  int effectiveBeatUnit(int fallback) => beatUnit ?? fallback;

  int capacityTicks(int fallbackBeats, int fallbackBeatUnit) =>
      effectiveBeats(fallbackBeats) *
      1920 ~/
      effectiveBeatUnit(fallbackBeatUnit);
}
