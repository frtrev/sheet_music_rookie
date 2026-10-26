import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/playback_instrument.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/services/score_playback_service.dart';
import 'package:sheet_music_rookie/transcription/transcription_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentMicrophone implements MicrophoneService {
  @override
  Stream<AudioFrame> get frames => const Stream.empty();
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

const xml =
    '<score-partwise><work><work-title>Wrong embedded title</work-title></work><part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note></measure></part></score-partwise>';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'import names come from filenames and legacy delivery prefixes are removed',
    () async {
      final root = await Directory.systemTemp.createTemp('names-test');
      addTearDown(() => root.delete(recursive: true));
      final folder = Directory('${root.path}/incoming-musicxml')..createSync();
      final service = CompositionStorageService();
      for (final name in [
        '1234567890123-Señor.musicxml',
        '12345678-1234-1234-1234-123456789012-Señor.musicxml',
        'Señor.musicxml',
      ]) {
        final file = File('${folder.path}/$name');
        await file.writeAsString(xml);
        expect(
          (await service.importFile(file.path)).composition.title,
          'Señor',
        );
      }
      final file = File('${root.path}/2026 Song.musicxml');
      await file.writeAsString(xml);
      expect(
        (await service.importFile(file.path)).composition.title,
        '2026 Song',
      );
    },
  );
  test(
    'BPM retimes events without changing the notation, and supports undo',
    () async {
      SharedPreferences.setMockInitialValues({});
      final engine = TranscriptionEngine(
        microphone: _SilentMicrophone(),
        clef: ClefType.treble,
        octaveRange: OctaveRange.standard,
      );
      addTearDown(engine.dispose);
      engine.insertManualNote(0, 60, NoteValue.quarter);
      engine.insertManualNote(480, 62, NoteValue.quarter);
      engine.setTempoBpm(240);
      expect(engine.rawEvents.map((e) => e.durationMs), [250, 250]);
      expect(
        engine.composition.value.measures.first.notes.map((n) => n.startTick),
        [0, 480],
      );
      expect(
        engine.composition.value.measures.first.notes.map(
          (n) => n.durationTicks,
        ),
        [480, 480],
      );
      engine.undo();
      expect(engine.composition.value.tempoBpm, 120);
      engine.redo();
      expect(engine.composition.value.tempoBpm, 240);
    },
  );
  test('instrument and tempo persist and export a MIDI program', () async {
    final root = await Directory.systemTemp.createTemp('sound-settings');
    addTearDown(() => root.delete(recursive: true));
    final service = CompositionStorageService(
      documentsDirectory: () async => root,
    );
    final importedFile = File('${root.path}/My song.musicxml');
    await importedFile.writeAsString(xml);
    final imported = await service.importFile(importedFile.path);
    final score = imported.composition.copyWith(
      playbackInstrument: PlaybackInstrument.flute,
    );
    final saved = await service.save(
      composition: score,
      rawEvents: imported.rawEvents,
    );
    expect(
      (await service.load(saved.path)).composition.playbackInstrument,
      PlaybackInstrument.flute,
    );
    final archive = ZipDecoder().decodeBytes(
      await File(saved.path).readAsBytes(),
    );
    expect(
      utf8.decode(archive.findFile('score.musicxml')!.content),
      contains('<midi-program>74</midi-program>'),
    );
  });
  test(
    'instrument voices produce distinct WAVs and tempo changes duration',
    () async {
      final root = await Directory.systemTemp.createTemp('voices-test');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/Notes.musicxml');
      await file.writeAsString(xml);
      final score = (await CompositionStorageService().importFile(file.path))
          .composition;
      const renderer = PianoWaveSynthesizer(sampleRate: 8000);
      final waves = [
        for (final voice in [
          PlaybackInstrument.piano,
          PlaybackInstrument.nylonGuitar,
          PlaybackInstrument.flute,
          PlaybackInstrument.organ,
        ])
          renderer.render(score.copyWith(playbackInstrument: voice))!,
      ];
      for (var i = 1; i < waves.length; i++) {
        expect(waves[i], isNot(equals(waves[0])));
      }
      final faster = renderer.render(
        score.copyWith(tempoBpm: score.tempoBpm * 2),
      )!;
      expect(faster.length - 44, (waves.first.length - 44) ~/ 2);
    },
  );
}
