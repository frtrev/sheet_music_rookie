import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';
import 'package:sheet_music_rookie/transcription/rhythm_quantizer.dart';

RawNoteEvent event(int start, int duration, {int midi = 60}) => RawNoteEvent(
  startTimeMs: start,
  endTimeMs: start + duration,
  frequencyHz: 261.63,
  midiPitch: midi,
  confidence: .95,
);

void main() {
  test('durations quantize to supported tick values at 120 BPM', () {
    const quantizer = RhythmQuantizer();
    expect(quantizer.quantizeDuration(125, 120), 120);
    expect(quantizer.quantizeDuration(375, 120), 360);
    expect(quantizer.quantizeDuration(500, 120), 480);
    expect(quantizer.quantizeDuration(750, 120), 720);
    expect(quantizer.quantizeDuration(1000, 120), 960);
    expect(quantizer.quantizeDuration(1500, 120), 1440);
    expect(quantizer.quantizeDuration(2000, 120), 1920);
  });

  test('measure builder creates measures and ties notes over a bar line', () {
    final events = <RawNoteEvent>[
      for (var i = 0; i < 15; i++) event(i * 125, 125),
      event(1875, 500, midi: 62),
    ];

    final measures = const MeasureBuilder().build(events, 120, 4);

    expect(measures, hasLength(2));
    expect(measures.first.notes.last.tieToNext, isTrue);
    expect(measures.last.notes.first.tieFromPrevious, isTrue);
    expect(
      measures
          .expand((measure) => measure.notes)
          .where((note) => note.midiPitch == 62)
          .map((note) => note.sourceEventIndex)
          .toSet(),
      {15},
    );
    expect(measures.last.notes.first.midiPitch, 62);
  });

  test('measure builder applies the selected octave range', () {
    final measures = const MeasureBuilder().build(
      [event(0, 500, midi: 60)],
      120,
      4,
      octaveTranspositionSemitones: 12,
    );

    expect(measures.single.notes.single.midiPitch, 48);
  });

  test('key signature accidentals are implied instead of repeated', () {
    final gMajor = const MeasureBuilder().build(
      [event(0, 500, midi: 66)],
      120,
      4,
      keySignature: KeySignature.gMajor,
    );
    final fMajor = const MeasureBuilder().build(
      [event(0, 500, midi: 70)],
      120,
      4,
      keySignature: KeySignature.fMajor,
    );

    expect(gMajor.single.notes.single.accidental, NoteAccidental.none);
    expect(gMajor.single.notes.single.flatSpelling, isFalse);
    expect(fMajor.single.notes.single.accidental, NoteAccidental.none);
    expect(fMajor.single.notes.single.flatSpelling, isTrue);
  });

  test(
    'all standard major key signatures from seven flats to sharps exist',
    () {
      expect(KeySignature.values, hasLength(15));
      expect(
        KeySignature.values.map((key) => key.accidentalCount).toSet(),
        equals({for (var count = -7; count <= 7; count++) count}),
      );
    },
  );

  test('4/4 bar keeps four visible beats when a note crosses the bar line', () {
    final measures = const MeasureBuilder().build(
      [event(0, 1000), event(1000, 500), event(1500, 2000)],
      120,
      4,
    );

    expect(measures, hasLength(2));
    expect(measures.first.notes.map((note) => note.durationTicks), [
      960,
      480,
      480,
    ]);
    expect(
      measures.first.notes.fold<int>(
        0,
        (total, note) => total + note.durationTicks,
      ),
      1920,
    );
    expect(measures.first.notes.last.tieToNext, isTrue);
    expect(measures.last.notes.first.tieFromPrevious, isTrue);
    expect(
      measures
          .expand((measure) => measure.notes)
          .every(
            (note) => NoteValue.values.any(
              (value) => value.ticks == note.durationTicks,
            ),
          ),
      isTrue,
    );
  });

  test('accidentals reset at the next measure', () {
    final measures = const MeasureBuilder().build(
      [
        event(0, 2000, midi: 61).copyWith(accidental: NoteAccidental.flat),
        event(2000, 500, midi: 62),
      ],
      120,
      4,
    );

    expect(measures.first.notes.first.accidental, NoteAccidental.flat);
    expect(measures[1].notes.first.accidental, NoteAccidental.none);
  });
}
