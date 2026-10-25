import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/pitch_detection_result.dart';
import 'package:sheet_music_rookie/music/performance_plan.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/services/melody_test_service.dart';
import 'package:sheet_music_rookie/services/practice_service.dart';
import 'package:sheet_music_rookie/services/score_playback_service.dart';

const forward =
    '<barline location="left"><repeat direction="forward"/></barline>';
String ending(int n, String type, {bool back = false}) =>
    '<barline location="${type == 'start' ? 'left' : 'right'}"><ending number="$n" type="$type"/>${back ? '<repeat direction="backward"/>' : ''}</barline>';
Composition score(List<List<String>> bars) => Composition(
  clef: ClefType.treble,
  beatsPerMeasure: 1,
  measures: [
    for (final (i, marks) in bars.indexed)
      Measure(
        index: i,
        barlines: marks,
        notes: [
          MusicalNote(
            midiPitch: 60 + i,
            startTick: 0,
            durationTicks: 480,
            sourceEventIndex: i,
          ),
        ],
      ),
  ],
);
List<int> order(Composition score) =>
    PerformancePlan(score).visits.map((v) => v.sourceIndex).toList();
Composition threeEndings() => score([
  [forward],
  [],
  [ending(1, 'start'), ending(1, 'stop', back: true)],
  [ending(2, 'start'), ending(2, 'stop')],
  [ending(3, 'start'), ending(3, 'discontinue')],
]);

void main() {
  test('first second and third endings repeat the common passage', () {
    final source = threeEndings();
    final plan = PerformancePlan(source);
    expect(order(source), [0, 1, 2, 0, 1, 3, 0, 1, 4]);
    expect(plan.sourceTickAt(1440), 0);
    expect(plan.sourceTickAt(2400), 1440);
    expect(plan.performanceTickAt(0, nearTick: 1500), 1440);
    expect(source.measures.length, 5);
  });
  test('explicit times and implicit start repeats are bounded', () {
    expect(
      order(
        score([
          [],
          ['<barline><repeat direction="backward" times="3"/></barline>'],
        ]),
      ),
      [0, 1, 0, 1, 0, 1],
    );
    expect(
      order(
        score([
          [forward],
          ['<barline><repeat direction="backward"/></barline>'],
          [],
        ]),
      ),
      [0, 1, 0, 1, 2],
    );
  });
  test('nested repeats restart on each outer pass', () {
    final source = score([
      [forward],
      [forward],
      ['<barline><repeat direction="backward"/></barline>'],
      ['<barline><repeat direction="backward"/></barline>'],
    ]);
    expect(order(source), [0, 1, 2, 1, 2, 3, 0, 1, 2, 1, 2, 3]);
  });
  test('comma separated endings and isolated labels do not drop music', () {
    final source = score([
      [forward],
      [
        '<barline location="left"><ending number="1,2" type="start"/></barline>',
        '<barline><ending number="1,2" type="stop"/><repeat direction="backward"/></barline>',
      ],
      [ending(3, 'start'), ending(3, 'discontinue')],
    ]);
    expect(order(source), [0, 1, 0, 1, 0, 2]);
    expect(
      order(
        score([
          [forward, ending(2, 'start')],
          [
            ending(2, 'stop'),
            '<barline><repeat direction="backward"/></barline>',
          ],
        ]),
      ),
      [0, 1, 0, 1],
    );
  });
  test(
    'piano practice and test share all passes and the cursor maps to the score',
    () {
      final source = threeEndings();
      final practice = PracticeSession(
        source,
        pitchStabilityMs: 0,
        articulationGapMs: 0,
        requiredDurationFraction: .1,
      );
      final test = MelodyTestSession(source);
      final expected = [60, 61, 62, 60, 61, 63, 60, 61, 64];
      expect(practice.targets.map((t) => t.soundingMidiPitch), expected);
      final wave = const PianoWaveSynthesizer(sampleRate: 8000).render(source)!;
      expect((wave.length - 44) ~/ 2, 36000); // Nine half-second measures.
      expect(test.cursorTickAt(const Duration(milliseconds: 1500)), 0);
      expect(test.hasReachedEnd(const Duration(milliseconds: 2500)), isFalse);
      expect(test.hasReachedEnd(const Duration(milliseconds: 4500)), isTrue);
      for (var time = 0; time < 4500; time += 20) {
        final midi = expected[time ~/ 500];
        test.addFrame(
          AudioFrame(Float64List(2048), time),
          pitch: PitchDetectionResult(
            timestampMs: time,
            frequencyHz: (440 * math.pow(2, (midi - 69) / 12)).toDouble(),
            midiNote: midi,
            noteName: 'Test',
            octave: 4,
            centsDeviation: 0,
            confidence: 1,
            rmsAmplitude: .2,
          ),
          voiceDetected: true,
        );
      }
      expect(test.finish().pitchScore, 100);
    },
  );

  test('practice advances through every pass before completing', () {
    final session = PracticeSession(
      threeEndings(),
      pitchStabilityMs: 0,
      articulationGapMs: 0,
      requiredDurationFraction: .1,
    );
    final pitches = [60, 61, 62, 60, 61, 63, 60, 61, 64];
    for (var i = 0; i < pitches.length; i++) {
      expect(session.completed, isFalse);
      expect(session.currentTarget!.soundingMidiPitch, pitches[i]);
      PracticeUpdate? update;
      for (final time in [i * 200, i * 200 + 100]) {
        update = session.process(
          PitchDetectionResult(
            timestampMs: time,
            frequencyHz: (440 * math.pow(2, (pitches[i] - 69) / 12)).toDouble(),
            midiNote: pitches[i],
            noteName: 'Test',
            octave: 4,
            centsDeviation: 0,
            confidence: 1,
            rmsAmplitude: .2,
          ),
          voiceDetected: true,
        );
      }
      expect(update, isNotNull);
      if (i == 2 || i == 5) expect(session.sourceTickAt(update!.cursorTick), 0);
      expect(update!.completed, i == pitches.length - 1);
    }
    expect(session.completed, isTrue);
  });

  test('a repeated single note requires two practice targets', () {
    final source = score([
      [forward, '<barline><repeat direction="backward"/></barline>'],
    ]);
    expect(PracticeSession(source, pitchStabilityMs: 0).targets.length, 2);
  });

  final example = Platform.environment['REPEAT_EXAMPLE'];
  test('Canto de Ofrendas imports and round-trips all repeat marks', () async {
    final root = await Directory.systemTemp.createTemp('repeat-example');
    addTearDown(() => root.delete(recursive: true));
    final storage = CompositionStorageService(
      documentsDirectory: () async => root,
    );
    final imported = await storage.importFile(example!);
    final plan = PerformancePlan(imported.composition);
    final expected = [
      for (final ending in [15, 20, 25]) ...[
        for (var i = 0; i < 11; i++) i,
        for (var i = ending - 4; i <= ending; i++) i,
      ],
      ...[for (var i = 26; i <= 41; i++) i],
      ...[for (var i = 26; i <= 36; i++) i, for (var i = 42; i <= 53; i++) i],
      ...[for (var i = 54; i <= 61; i++) i],
      ...[for (var i = 54; i <= 57; i++) i, for (var i = 62; i <= 75; i++) i],
      ...[
        for (var pass = 0; pass < 2; pass++) ...[
          for (var i = 76; i <= 81; i++) i,
        ],
      ],
    ];
    expect(plan.visits.map((v) => v.sourceIndex).toList(), expected);
    final saved = await storage.save(
      composition: imported.composition,
      rawEvents: imported.rawEvents,
    );
    final reopened = await storage.load(saved.path);
    expect(order(reopened.composition), expected);
    final archive = ZipDecoder().decodeBytes(
      await File(saved.path).readAsBytes(),
    );
    final plain = File('${root.path}/export.musicxml');
    await plain.writeAsString(
      utf8.decode(archive.findFile('score.musicxml')!.content),
    );
    expect(order((await storage.importFile(plain.path)).composition), expected);

    expect(
      reopened.composition.measures.expand((m) => m.barlines),
      imported.composition.measures.expand((m) => m.barlines),
    );
    // ignore: avoid_print
    print(
      'Verified ${imported.composition.measures.length} written measures, ${plan.visits.length} performed visits.',
    );
  }, skip: example == null ? 'Set REPEAT_EXAMPLE to a local MXL path.' : false);
}
