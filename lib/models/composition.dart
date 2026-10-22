import 'measure.dart';

enum ClefType { treble, bass }

enum OctaveRange {
  twoOctavesDown(-24, '15 down', '15mb'),
  octaveDown(-12, '8 down', '8vb'),
  standard(0, 'Standard', ''),
  octaveUp(12, '8 up', '8va'),
  twoOctavesUp(24, '15 up', '15ma');

  const OctaveRange(this.semitones, this.label, this.notationLabel);
  final int semitones;
  final String label;
  final String notationLabel;
}

enum RecordingMode { fixedTempo, freeSinging }

enum KeySignature {
  cMajor('C Major', 0),
  gMajor('G Major', 1),
  dMajor('D Major', 2),
  aMajor('A Major', 3),
  eMajor('E Major', 4),
  bMajor('B Major', 5),
  fSharpMajor('F♯ Major', 6),
  cSharpMajor('C♯ Major', 7),
  fMajor('F Major', -1),
  bFlatMajor('B♭ Major', -2),
  eFlatMajor('E♭ Major', -3),
  aFlatMajor('A♭ Major', -4),
  dFlatMajor('D♭ Major', -5),
  gFlatMajor('G♭ Major', -6),
  cFlatMajor('C♭ Major', -7);

  const KeySignature(this.name, this.accidentalCount);
  final String name;
  final int accidentalCount;

  String get symbols => accidentalCount > 0
      ? List.filled(accidentalCount, '♯').join()
      : List.filled(-accidentalCount, '♭').join();

  String get label => symbols.isEmpty ? name : '$name $symbols';

  int alterationForNaturalPitchClass(int pitchClass) {
    const sharpOrder = [5, 0, 7, 2, 9, 4, 11];
    const flatOrder = [11, 4, 9, 2, 7, 0, 5];
    if (accidentalCount > 0 &&
        sharpOrder.take(accidentalCount).contains(pitchClass)) {
      return 1;
    }
    if (accidentalCount < 0 &&
        flatOrder.take(-accidentalCount).contains(pitchClass)) {
      return -1;
    }
    return 0;
  }
}

class Composition {
  const Composition({
    this.title = 'Untitled Composition',
    this.keySignature = KeySignature.cMajor,
    this.beatsPerMeasure = 4,
    this.beatUnit = 4,
    this.tempoBpm = 120,
    required this.clef,
    this.octaveRange = OctaveRange.standard,
    this.recordingMode = RecordingMode.fixedTempo,
    this.metronomeEnabled = false,
    this.microphoneActive = true,
    this.measures = const [Measure(index: 0)],
  });

  final String title;
  final KeySignature keySignature;
  final int beatsPerMeasure;
  final int beatUnit;
  final int tempoBpm;
  final ClefType clef;
  final OctaveRange octaveRange;
  final RecordingMode recordingMode;
  final bool metronomeEnabled;
  final bool microphoneActive;
  final List<Measure> measures;

  Composition copyWith({
    List<Measure>? measures,
    bool? microphoneActive,
    bool? metronomeEnabled,
    KeySignature? keySignature,
  }) {
    return Composition(
      title: title,
      keySignature: keySignature ?? this.keySignature,
      beatsPerMeasure: beatsPerMeasure,
      beatUnit: beatUnit,
      tempoBpm: tempoBpm,
      clef: clef,
      octaveRange: octaveRange,
      recordingMode: recordingMode,
      metronomeEnabled: metronomeEnabled ?? this.metronomeEnabled,
      microphoneActive: microphoneActive ?? this.microphoneActive,
      measures: measures ?? this.measures,
    );
  }
}
