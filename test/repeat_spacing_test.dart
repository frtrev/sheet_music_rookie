import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';

const startRepeat =
    '<barline location="left"><repeat direction="forward"/></barline>';
const endRepeat =
    '<barline location="right"><repeat direction="backward"/></barline>';
const note = MusicalNote(midiPitch: 60, startTick: 0, durationTicks: 480);
Composition score(
  List<String> marks, {
  bool later = false,
  KeySignature key = KeySignature.cMajor,
}) => Composition(
  clef: ClefType.treble,
  keySignature: key,
  measures: [
    if (later) const Measure(index: 0, notes: [note]),
    Measure(
      index: later ? 1 : 0,
      notes: const [note],
      barlines: marks,
      beatsPerMeasure: 1,
      beatUnit: 4,
    ),
  ],
);

void main() {
  test('start repeat clears first time signature and preserves note selection alignment', () {
    final repeated = score([startRepeat]);
    final repeatDotRight = ScoreLayout.measureLeft(repeated, 0) + 4 + 11 + 2.5;
    expect(
      ScoreLayout.timeSignatureX(repeated, 0),
      greaterThan(repeatDotRight + 5),
    );
    final center = ScoreLayout.noteCenter(repeated, 0, note);
    expect(
      center.dx - 7,
      greaterThan(ScoreLayout.timeSignatureX(repeated, 0) + 22),
    );
    expect(ScoreLayout.tickAtX(repeated, center.dx), 0);
    expect(ScoreLayout.cursorX(repeated, 0), center.dx);
  });

  test('repeat spacing also clears a changed meter in a later measure', () {
    final repeated = score([startRepeat], later: true);
    final plain = score([], later: true);
    final repeatDotRight = ScoreLayout.measureLeft(repeated, 1) + 17.5;
    expect(
      ScoreLayout.timeSignatureX(repeated, 1),
      greaterThan(repeatDotRight + 5),
    );
    expect(
      ScoreLayout.contentStart(repeated, 1),
      greaterThan(ScoreLayout.contentStart(plain, 1)),
    );
    final center = ScoreLayout.noteCenter(repeated, 1, note);
    expect(ScoreLayout.tickAtX(repeated, center.dx), 1920);
  });

  test('ordinary and end-repeat measures retain their original spacing', () {
    for (final later in [false, true]) {
      final plain = score([], later: later);
      final ending = score([endRepeat], later: later);
      final index = later ? 1 : 0;
      expect(
        ScoreLayout.contentStart(ending, index),
        ScoreLayout.contentStart(plain, index),
      );
      expect(
        ScoreLayout.timeSignatureX(ending, index),
        ScoreLayout.timeSignatureX(plain, index),
      );
      expect(
        ScoreLayout.timeSignatureX(plain, index),
        ScoreLayout.measureLeft(plain, index) + (later ? 7 : 0),
      );
    }
  });

  test('repeat inset leaves the same room for key signatures before the first note', () {
    for (final key in KeySignature.values) {
      final plain = score([], key: key);
      final repeated = score([startRepeat], key: key);
      expect(
        ScoreLayout.contentStart(repeated, 0) -
            ScoreLayout.timeSignatureX(repeated, 0),
        ScoreLayout.contentStart(plain, 0) -
            ScoreLayout.timeSignatureX(plain, 0),
      );
    }
  });
}
