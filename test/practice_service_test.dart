import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/pitch_detection_result.dart';
import 'package:sheet_music_rookie/services/practice_service.dart';

PitchDetectionResult detected(int timestampMs, int midi) =>
    PitchDetectionResult(
      timestampMs: timestampMs,
      frequencyHz: 440,
      midiNote: midi,
      noteName: 'Test',
      octave: 4,
      centsDeviation: 0,
      confidence: 1,
      rmsAmplitude: .2,
    );

void main() {
  test(
    'practice advances only after the expected pitch is held long enough',
    () {
      const composition = Composition(
        clef: ClefType.treble,
        keySignature: KeySignature.gMajor,
        octaveRange: OctaveRange.octaveUp,
        tempoBpm: 120,
        measures: [
          Measure(
            index: 0,
            notes: [
              MusicalNote(
                midiPitch: 65,
                startTick: 1440,
                durationTicks: 480,
                sourceEventIndex: 0,
                tieToNext: true,
              ),
            ],
          ),
          Measure(
            index: 1,
            notes: [
              MusicalNote(
                midiPitch: 65,
                startTick: 0,
                durationTicks: 480,
                sourceEventIndex: 0,
                tieFromPrevious: true,
              ),
              MusicalNote(
                midiPitch: 0,
                startTick: 480,
                durationTicks: 480,
                isRest: true,
              ),
              MusicalNote(
                midiPitch: 60,
                startTick: 960,
                durationTicks: 480,
                sourceEventIndex: 1,
              ),
            ],
          ),
        ],
      );
      final session = PracticeSession(composition, pitchStabilityMs: 100);

      expect(session.targets, hasLength(2));
      expect(session.currentTarget?.startTick, 1440);
      expect(session.targets.first.durationTicks, 960);
      expect(session.targets.first.soundingMidiPitch, 78); // F♯5 sounding.
      expect(session.process(detected(0, 78), voiceDetected: true), isNull);
      expect(session.progress, 0);
      expect(session.process(detected(599, 78), voiceDetected: true), isNull);
      expect(session.progress, closeTo(599 / 600, .001));
      final advanced = session.process(detected(600, 78), voiceDetected: true);
      expect(advanced?.cursorTick, 2880);
      expect(advanced?.completed, isFalse);
      expect(session.progress, 0);

      // A wrong pitch resets the hold timer for the next target.
      expect(session.process(detected(700, 71), voiceDetected: true), isNull);
      expect(session.progress, 0);
      expect(session.process(detected(800, 72), voiceDetected: true), isNull);
      final completed = session.process(
        detected(1100, 72),
        voiceDetected: true,
      );
      expect(completed?.completed, isTrue);
      expect(completed?.cursorTick, 3360);
    },
  );

  test('silence resets practice pitch stability', () {
    const composition = Composition(
      clef: ClefType.treble,
      tempoBpm: 120,
      measures: [
        Measure(
          index: 0,
          notes: [MusicalNote(midiPitch: 60, startTick: 0, durationTicks: 480)],
        ),
      ],
    );
    final session = PracticeSession(composition, pitchStabilityMs: 100);

    session.process(detected(0, 60), voiceDetected: true);
    session.process(null, voiceDetected: false);
    expect(session.process(detected(400, 60), voiceDetected: true), isNull);
    expect(
      session.process(detected(700, 60), voiceDetected: true)?.completed,
      isTrue,
    );
  });
}
