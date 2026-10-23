import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'composition round-trips through a standards-shaped MXL archive',
    () async {
      final root = await Directory.systemTemp.createTemp('rookie-mxl-test-');
      addTearDown(() => root.delete(recursive: true));
      final service = CompositionStorageService(
        documentsDirectory: () async => root,
      );
      const events = [
        RawNoteEvent(
          startTimeMs: 0,
          endTimeMs: 500,
          frequencyHz: 261.63,
          midiPitch: 60,
          confidence: .94,
          accidental: NoteAccidental.natural,
          tieToNext: true,
        ),
        RawNoteEvent(
          startTimeMs: 500,
          endTimeMs: 1000,
          frequencyHz: 261.63,
          midiPitch: 60,
          confidence: .91,
        ),
        RawNoteEvent(
          startTimeMs: 1000,
          endTimeMs: 1500,
          frequencyHz: 0,
          midiPitch: 0,
          confidence: 1,
          accidental: NoteAccidental.none,
          isRest: true,
        ),
      ];
      final measures = const MeasureBuilder().build(
        events,
        120,
        4,
        keySignature: KeySignature.gMajor,
      );
      final composition = Composition(
        title: 'Saved Melody',
        clef: ClefType.treble,
        keySignature: KeySignature.gMajor,
        octaveRange: OctaveRange.octaveUp,
        metronomeMode: MetronomeMode.single,
        metronomeVolume: .35,
        playbackVolume: .8,
        measures: measures,
      );

      final saved = await service.save(
        composition: composition,
        rawEvents: events,
      );
      expect(saved.path, endsWith('.mxl'));
      final archive = ZipDecoder().decodeBytes(
        await File(saved.path).readAsBytes(),
      );
      expect(archive.first.name, 'mimetype');
      expect(archive.first.compression, CompressionType.none);
      expect(
        ascii.decode(archive.first.content),
        'application/vnd.recordare.musicxml',
      );
      expect(archive.findFile('META-INF/container.xml'), isNotNull);
      final score = utf8.decode(archive.findFile('score.musicxml')!.content);
      final document = XmlDocument.parse(score);
      expect(document.rootElement.name.local, 'score-partwise');
      expect(
        document.findAllElements('work-title').single.innerText,
        'Saved Melody',
      );
      expect(document.findAllElements('fifths').single.innerText, '1');
      expect(document.findAllElements('rest'), isNotEmpty);
      expect(
        document
            .findAllElements('tie')
            .any((element) => element.getAttribute('type') == 'start'),
        isTrue,
      );

      final loaded = await service.load(saved.path);
      expect(loaded.composition.title, 'Saved Melody');
      expect(loaded.composition.keySignature, KeySignature.gMajor);
      expect(loaded.composition.octaveRange, OctaveRange.octaveUp);
      expect(loaded.composition.metronomeMode, MetronomeMode.single);
      expect(loaded.composition.metronomeVolume, .35);
      expect(loaded.composition.playbackVolume, .8);
      expect(loaded.rawEvents, hasLength(3));
      expect(loaded.rawEvents.first.tieToNext, isTrue);
      expect(loaded.rawEvents.last.isRest, isTrue);
      expect(loaded.composition.measures.first.notes, isNotEmpty);
    },
  );

  test('saving an opened composition updates the same local file', () async {
    final root = await Directory.systemTemp.createTemp('rookie-mxl-update-');
    addTearDown(() => root.delete(recursive: true));
    final service = CompositionStorageService(
      documentsDirectory: () async => root,
    );
    const composition = Composition(title: 'Draft', clef: ClefType.bass);

    final first = await service.save(
      composition: composition,
      rawEvents: const [],
    );
    final second = await service.save(
      composition: composition.copyWith(title: 'Revised'),
      rawEvents: const [],
      existingPath: first.path,
    );

    expect(second.path, first.path);
    final listed = await service.listSaved();
    expect(listed, hasLength(1));
    expect(listed.single.composition.title, 'Revised');
  });
}
