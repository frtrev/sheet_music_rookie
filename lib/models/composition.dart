import 'playback_instrument.dart';
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

enum MetronomeMode {
  off('Metronome off'),
  accented('Metronome on'),
  single('Metronome single');

  const MetronomeMode(this.label);
  final String label;

  MetronomeMode get next => switch (this) {
    MetronomeMode.off => MetronomeMode.accented,
    MetronomeMode.accented => MetronomeMode.single,
    MetronomeMode.single => MetronomeMode.off,
  };
}

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
    this.playbackInstrument = PlaybackInstrument.piano,
    required this.clef,
    this.octaveRange = OctaveRange.standard,
    this.recordingMode = RecordingMode.fixedTempo,
    this.metronomeMode = MetronomeMode.off,
    this.metronomeVolume = .55,
    this.playbackVolume = 1,
    this.microphoneActive = false,
    this.measures = const [Measure(index: 0)],
  });

  final String title;
  final KeySignature keySignature;
  final int beatsPerMeasure;
  final int beatUnit;
  final int tempoBpm;
  final PlaybackInstrument playbackInstrument;
  final ClefType clef;
  final OctaveRange octaveRange;
  final RecordingMode recordingMode;
  final MetronomeMode metronomeMode;
  final double metronomeVolume;
  final double playbackVolume;
  final bool microphoneActive;
  final List<Measure> measures;

  int measureCapacityTicks(int index) {
    if (measures.isEmpty) return beatsPerMeasure * 1920 ~/ beatUnit;
    final safeIndex = index.clamp(0, measures.length - 1).toInt();
    return measures[safeIndex].capacityTicks(beatsPerMeasure, beatUnit);
  }

  int measureStartTick(int index) {
    var result = 0;
    for (
      var current = 0;
      current < index && current < measures.length;
      current++
    ) {
      result += measureCapacityTicks(current);
    }
    return result;
  }

  int get editableEndTick {
    if (measures.isEmpty) return beatsPerMeasure * 1920 ~/ beatUnit;
    return measureStartTick(measures.length);
  }

  int measureIndexAtTick(int tick) {
    if (measures.isEmpty) return 0;
    final bounded = tick.clamp(0, editableEndTick).toInt();
    var start = 0;
    for (var index = 0; index < measures.length; index++) {
      final end = start + measureCapacityTicks(index);
      if (bounded < end || index == measures.length - 1) return index;
      start = end;
    }
    return measures.length - 1;
  }

  Composition copyWith({
    String? title,
    List<Measure>? measures,
    bool? microphoneActive,
    MetronomeMode? metronomeMode,
    double? metronomeVolume,
    double? playbackVolume,
    KeySignature? keySignature,
    OctaveRange? octaveRange,
    int? beatsPerMeasure,
    int? beatUnit,
    int? tempoBpm,
    PlaybackInstrument? playbackInstrument,
  }) {
    return Composition(
      title: title ?? this.title,
      keySignature: keySignature ?? this.keySignature,
      beatsPerMeasure: beatsPerMeasure ?? this.beatsPerMeasure,
      beatUnit: beatUnit ?? this.beatUnit,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      playbackInstrument: playbackInstrument ?? this.playbackInstrument,
      clef: clef,
      octaveRange: octaveRange ?? this.octaveRange,
      recordingMode: recordingMode,
      metronomeMode: metronomeMode ?? this.metronomeMode,
      metronomeVolume: metronomeVolume ?? this.metronomeVolume,
      playbackVolume: playbackVolume ?? this.playbackVolume,
      microphoneActive: microphoneActive ?? this.microphoneActive,
      measures: measures ?? this.measures,
    );
  }
}
