import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/pitch_detection_result.dart';
import 'package:sheet_music_rookie/services/melody_test_service.dart';

PitchDetectionResult pitch(int timestampMs, int midi) => PitchDetectionResult(
  timestampMs: timestampMs,
  frequencyHz: (440 * math.pow(2, (midi - 69) / 12)).toDouble(),
  midiNote: midi,
  noteName: 'Test',
  octave: 4,
  centsDeviation: 0,
  confidence: 1,
  rmsAmplitude: .2,
);

AudioFrame frame(int timestampMs) => AudioFrame(
  Float64List.fromList(
    List.generate(2048, (index) => math.sin(index * .08) * .08),
  ),
  timestampMs,
);

const composition = Composition(
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

void main() {
  test(
    'an in-tune and in-time melody receives a high score and matchup WAV',
    () {
      final session = MelodyTestSession(composition);
      for (var time = 0; time < 1000; time += 20) {
        final midi = time < 500 ? 69 : 71;
        session.addFrame(
          frame(time),
          pitch: pitch(time, midi),
          voiceDetected: true,
        );
      }

      final result = session.finish();

      expect(result.score, greaterThanOrEqualTo(95));
      expect(result.pitchScore, 100);
      expect(result.timingScore, greaterThanOrEqualTo(95));
      expect(result.matchupWave, isNotNull);
      expect(String.fromCharCodes(result.matchupWave!.sublist(8, 12)), 'WAVE');
    },
  );

  test('wrong pitches score below the matching performance', () {
    MelodyTestResult attempt(int midi) {
      final session = MelodyTestSession(composition);
      for (var time = 0; time < 1000; time += 20) {
        session.addFrame(
          frame(time),
          pitch: pitch(time, midi),
          voiceDetected: true,
        );
      }
      return session.finish();
    }

    final matching = attempt(69);
    final wrong = attempt(76);

    expect(wrong.pitchScore, lessThan(matching.pitchScore));
    expect(wrong.score, lessThan(matching.score));
  });

  test('silence does not stop a test before the score reaches its end', () {
    final session = MelodyTestSession(composition);

    expect(
      session.addFrame(frame(100), pitch: pitch(100, 69), voiceDetected: true),
      isFalse,
    );
    expect(
      session.addFrame(frame(600), pitch: null, voiceDetected: false),
      isFalse,
    );
    expect(
      session.addFrame(frame(1100), pitch: null, voiceDetected: false),
      isTrue,
    );
  });

  test('note-led test waits for any detected pitch before moving the cursor', () {
    final session = MelodyTestSession(composition);

    session.addFrame(frame(100), pitch: null, voiceDetected: false);
    expect(session.timelineStarted, isFalse);
    expect(session.currentCursorTick, isNull);
    expect(session.currentExpectedMidiPitch, 69);

    session.addFrame(
      frame(200),
      pitch: pitch(200, 60),
      voiceDetected: true,
    );
    expect(session.timelineStarted, isTrue);
    expect(session.currentCursorTick, 0);

    session.addFrame(frame(700), pitch: null, voiceDetected: false);
    expect(session.currentCursorTick, 480);
    expect(session.currentExpectedMidiPitch, 71);
  });

  test('a leading rest starts the test timeline immediately', () {
    const withLeadingRest = Composition(
      clef: ClefType.treble,
      tempoBpm: 120,
      measures: [
        Measure(
          index: 0,
          notes: [
            MusicalNote(
              midiPitch: 0,
              startTick: 0,
              durationTicks: 480,
              isRest: true,
            ),
            MusicalNote(midiPitch: 69, startTick: 480, durationTicks: 480),
          ],
        ),
      ],
    );
    final session = MelodyTestSession(withLeadingRest);

    session.addFrame(frame(100), pitch: null, voiceDetected: false);
    expect(session.timelineStarted, isTrue);
    expect(session.currentCursorTick, 0);
    expect(session.currentExpectedMidiPitch, isNull);

    session.addFrame(frame(600), pitch: null, voiceDetected: false);
    expect(session.currentCursorTick, 480);
    expect(session.currentExpectedMidiPitch, 69);
  });
}
