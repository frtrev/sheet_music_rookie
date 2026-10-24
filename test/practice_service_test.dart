import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/pitch_detection_result.dart';
import 'package:sheet_music_rookie/models/voice_detection_settings.dart';
import 'package:sheet_music_rookie/services/practice_service.dart';

PitchDetectionResult detected(int timestampMs, int midi) =>
    PitchDetectionResult(
      timestampMs: timestampMs,
      frequencyHz: (440 * math.pow(2, (midi - 69) / 12)).toDouble(),
      midiNote: midi,
      noteName: 'Test',
      octave: 4,
      centsDeviation: 0,
      confidence: 1,
      rmsAmplitude: .2,
    );

PitchDetectionResult detectedAtCents(
  int timestampMs,
  int targetMidi,
  double cents,
) => PitchDetectionResult(
  timestampMs: timestampMs,
  frequencyHz: (440 * math.pow(2, (targetMidi - 69) / 12 + cents / 1200))
      .toDouble(),
  midiNote: targetMidi,
  noteName: 'Test',
  octave: 4,
  centsDeviation: cents,
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
      expect(advanced?.cursorTick, 2400);
      expect(advanced?.completed, isFalse);
      expect(session.progress, 0);

      // The written eighth-rest must elapse before the next note can begin.
      expect(
        session.process(null, voiceDetected: false, timestampMs: 650),
        isNull,
      );
      expect(
        session.process(null, voiceDetected: false, timestampMs: 1149),
        isNull,
      );
      expect(
        session
            .process(null, voiceDetected: false, timestampMs: 1150)
            ?.cursorTick,
        2880,
      );

      // A wrong pitch does not earn time for the next target.
      expect(session.process(detected(1200, 71), voiceDetected: true), isNull);
      expect(session.progress, 0);
      expect(session.process(detected(1250, 72), voiceDetected: true), isNull);
      final completed = session.process(
        detected(1550, 72),
        voiceDetected: true,
      );
      expect(completed?.completed, isTrue);
      expect(completed?.cursorTick, 3360);
    },
  );

  test('silence does not count toward beginner practice progress', () {
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

  test('practice accepts pitch inside the configurable cents range', () {
    const composition = Composition(
      clef: ClefType.treble,
      tempoBpm: 120,
      measures: [
        Measure(
          index: 0,
          notes: [MusicalNote(midiPitch: 69, startTick: 0, durationTicks: 480)],
        ),
      ],
    );
    final session = PracticeSession(
      composition,
      pitchStabilityMs: 100,
      pitchToleranceCents: 30,
      requiredDurationFraction: .1,
    );

    expect(
      session.process(detectedAtCents(0, 69, 35), voiceDetected: true),
      isNull,
    );
    expect(session.progress, 0);

    session.pitchToleranceCents = 40;
    expect(
      session.process(detectedAtCents(100, 69, 35), voiceDetected: true),
      isNull,
    );
    expect(
      session
          .process(detectedAtCents(200, 69, 35), voiceDetected: true)
          ?.completed,
      isTrue,
    );
  });

  test('beginner keeps progress, medium resets, and advanced restarts', () {
    const oneNote = Composition(
      clef: ClefType.treble,
      tempoBpm: 120,
      measures: [
        Measure(
          index: 0,
          notes: [MusicalNote(midiPitch: 69, startTick: 0, durationTicks: 480)],
        ),
      ],
    );
    final beginner = PracticeSession(
      oneNote,
      pitchStabilityMs: 100,
      requiredDurationFraction: .6,
    );
    beginner.process(detected(0, 69), voiceDetected: true);
    beginner.process(detected(150, 69), voiceDetected: true);
    expect(beginner.progress, .5);
    beginner.process(detected(200, 67), voiceDetected: true);
    expect(beginner.progress, .5);
    beginner.process(detected(300, 69), voiceDetected: true);
    expect(
      beginner.process(detected(450, 69), voiceDetected: true)?.completed,
      isTrue,
    );

    final medium = PracticeSession(
      oneNote,
      pitchStabilityMs: 100,
      difficulty: PracticeDifficulty.medium,
      requiredDurationFraction: .6,
    );
    medium.process(detected(0, 69), voiceDetected: true);
    medium.process(detected(150, 69), voiceDetected: true);
    expect(medium.progress, .5);
    medium.process(detected(200, 67), voiceDetected: true);
    expect(medium.progress, 0);

    const twoNotes = Composition(
      clef: ClefType.treble,
      tempoBpm: 120,
      measures: [
        Measure(
          index: 0,
          notes: [
            MusicalNote(midiPitch: 69, startTick: 0, durationTicks: 480),
            MusicalNote(midiPitch: 71, startTick: 480, durationTicks: 480),
          ],
        ),
      ],
    );
    final advanced = PracticeSession(
      twoNotes,
      pitchStabilityMs: 100,
      difficulty: PracticeDifficulty.advanced,
      requiredDurationFraction: .1,
    );
    advanced.process(detected(0, 69), voiceDetected: true);
    expect(
      advanced.process(detected(100, 69), voiceDetected: true)?.cursorTick,
      480,
    );
    expect(
      advanced.process(null, voiceDetected: false, timestampMs: 110),
      isNull,
    );
    expect(
      advanced
          .process(null, voiceDetected: false, timestampMs: 145)
          ?.cursorTick,
      480,
    );
    advanced.process(detected(200, 71), voiceDetected: true);
    advanced.process(detected(250, 71), voiceDetected: true);
    final restarted = advanced.process(detected(260, 69), voiceDetected: true);
    expect(restarted?.cursorTick, 0);
    expect(advanced.currentTarget?.soundingMidiPitch, 69);
    expect(advanced.progress, 0);
  });

  test('a sustained pitch cannot complete consecutive repeated notes', () {
    const composition = Composition(
      clef: ClefType.treble,
      tempoBpm: 120,
      measures: [
        Measure(
          index: 0,
          notes: [
            MusicalNote(midiPitch: 69, startTick: 0, durationTicks: 480),
            MusicalNote(midiPitch: 69, startTick: 480, durationTicks: 480),
          ],
        ),
      ],
    );
    final session = PracticeSession(
      composition,
      pitchStabilityMs: 100,
      articulationGapMs: 35,
      requiredDurationFraction: .1,
    );

    session.process(detected(0, 69), voiceDetected: true);
    expect(
      session.process(detected(100, 69), voiceDetected: true)?.cursorTick,
      480,
    );

    // Holding the same syllable cannot spill progress into the next note.
    expect(session.process(detected(200, 69), voiceDetected: true), isNull);
    expect(session.process(detected(300, 69), voiceDetected: true), isNull);
    expect(session.progress, 0);

    // A short articulation gap unlocks the repeated note.
    expect(
      session.process(null, voiceDetected: false, timestampMs: 310),
      isNull,
    );
    expect(
      session.process(null, voiceDetected: false, timestampMs: 345)?.cursorTick,
      480,
    );
    session.process(detected(400, 69), voiceDetected: true);
    expect(
      session.process(detected(500, 69), voiceDetected: true)?.completed,
      isTrue,
    );
  });
}
