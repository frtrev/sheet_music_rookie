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

class Composition {
  const Composition({
    this.title = 'Untitled Composition',
    this.keySignature = 'C Major',
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
  final String keySignature;
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
  }) {
    return Composition(
      title: title,
      keySignature: keySignature,
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
