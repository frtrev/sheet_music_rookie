import 'dart:io';
import 'dart:typed_data';

import 'package:dart_melty_soundfont/dart_melty_soundfont.dart' as sf;
import 'package:dart_melty_soundfont/soundfont.dart' as fonts;
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/general_user_soundfont.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/playback_instrument.dart';
import 'package:sheet_music_rookie/services/score_playback_service.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/music/performance_plan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ByteData bank;
  late fonts.SoundFont font;
  setUpAll(() async {
    bank = ByteData.sublistView(
      await File(GeneralUserSoundFont.asset).readAsBytes(),
    );
    font = fonts.SoundFont.fromByteData(bank);
  });
  test('every curated instrument exists in bank zero and produces sound', () {
    expect(
      PlaybackInstrument.values.map((i) => i.midiProgram).toSet().length,
      PlaybackInstrument.values.length,
    );
    final synth = sf.Synthesizer.loadByteData(
      bank,
      sf.SynthesizerSettings(sampleRate: 24000, enableReverbAndChorus: false),
    );
    for (final instrument in PlaybackInstrument.values) {
      final index = font.presets.indexWhere(
        (p) => p.bankNumber == 0 && p.patchNumber == instrument.midiProgram - 1,
      );
      expect(index, greaterThanOrEqualTo(0), reason: instrument.label);
      expect(instrument.midiProgram, lessThanOrEqualTo(80));
      expect(['Keyboards', 'Strings', 'Winds'], contains(instrument.family));
      synth.reset();
      synth.selectPreset(channel: 0, preset: index);
      synth.noteOn(channel: 0, key: 60, velocity: 100);
      final l = Float32List(12000), r = Float32List(12000);
      synth.render(l, r);
      expect(
        l.any((s) => s.abs() > .0001) || r.any((s) => s.abs() > .0001),
        isTrue,
        reason: instrument.label,
      );
    }
  });
  test(
    'sampled score rendering respects silence, duration, and selected program',
    () {
      const score = Composition(
        clef: ClefType.treble,
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
              MusicalNote(midiPitch: 60, startTick: 480, durationTicks: 480),
            ],
          ),
        ],
      );
      final renderer = PianoWaveSynthesizer(soundFont: bank);
      final piano = renderer.render(score)!;
      final flute = renderer.render(
        score.copyWith(playbackInstrument: PlaybackInstrument.flute),
      )!;
      expect(flute, isNot(equals(piano)));
      expect(piano.length, 44 + (24000 * 1.35).round() * 2);
      final pcm = ByteData.sublistView(piano);
      for (var i = 44; i < 44 + 24000; i += 2) {
        expect(pcm.getInt16(i, Endian.little), 0);
      }
      expect(piano.sublist(44 + 24000).any((v) => v != 0), isTrue);
      expect(pcm.getInt16(piano.length - 2, Endian.little), 0);
    },
  );
  test(
    'the bundled bank can load through Flutter assets and is cached',
    () async {
      final first = await GeneralUserSoundFont.load();
      final second = await GeneralUserSoundFont.load();
      expect(identical(first, second), isTrue);
      expect(first.length, bank.lengthInBytes);
    },
  );
  final example = Platform.environment['GENERALUSER_EXAMPLE'];
  test(
    'renders a complete imported score with repeats using GeneralUser GS',
    () async {
      final score = (await CompositionStorageService().importFile(example!))
          .composition;
      final plan = PerformancePlan(score);
      final watch = Stopwatch()..start();
      final wave = PianoWaveSynthesizer(soundFont: bank).render(score)!;
      watch.stop();
      final total = plan.expanded.measures.fold<int>(
        0,
        (end, m) => m.notes.fold<int>(end, (current, n) {
          final candidate =
              plan.expanded.measureStartTick(m.index) +
              n.startTick +
              n.durationTicks;
          return candidate > current ? candidate : current;
        }),
      );
      final expectedFrames =
          (total * 60 / score.tempoBpm / 480 * 24000).ceil() + 8400;
      expect(wave.length, 44 + expectedFrames * 2);
      // ignore: avoid_print
      print(
        'Rendered ${plan.visits.length} performed measures (${(expectedFrames / 24000).toStringAsFixed(1)} seconds) in ${watch.elapsedMilliseconds} ms.',
      );
    },
    skip: example == null
        ? 'Set GENERALUSER_EXAMPLE to render a local full score.'
        : false,
  );
}
