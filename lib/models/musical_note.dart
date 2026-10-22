enum NoteAccidental { automatic, none, sharp, flat, natural }

enum NoteValue {
  sixteenth(120, 120, 'Sixteenth'),
  eighth(240, 240, 'Eighth'),
  dottedEighth(360, 240, 'Dotted eighth'),
  quarter(480, 480, 'Quarter'),
  dottedQuarter(720, 480, 'Dotted quarter'),
  half(960, 960, 'Half'),
  dottedHalf(1440, 960, 'Dotted half'),
  whole(1920, 1920, 'Whole');

  const NoteValue(this.ticks, this.baseTicks, this.label);
  final int ticks;
  final int baseTicks;
  final String label;

  bool get isDotted => ticks != baseTicks;
}

class MusicalNote {
  const MusicalNote({
    required this.midiPitch,
    required this.startTick,
    required this.durationTicks,
    this.sourceEventIndex = -1,
    this.accidental = NoteAccidental.automatic,
    this.isRest = false,
    this.tieFromPrevious = false,
    this.tieToNext = false,
  });

  final int midiPitch;
  final int startTick;
  final int durationTicks;
  final int sourceEventIndex;
  final NoteAccidental accidental;
  final bool isRest;
  final bool tieFromPrevious;
  final bool tieToNext;

  MusicalNote copyWith({NoteAccidental? accidental}) => MusicalNote(
    midiPitch: midiPitch,
    startTick: startTick,
    durationTicks: durationTicks,
    sourceEventIndex: sourceEventIndex,
    accidental: accidental ?? this.accidental,
    isRest: isRest,
    tieFromPrevious: tieFromPrevious,
    tieToNext: tieToNext,
  );

  NoteValue get value => NoteValue.values.reduce(
    (a, b) => (a.ticks - durationTicks).abs() <= (b.ticks - durationTicks).abs()
        ? a
        : b,
  );
}
