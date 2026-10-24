import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
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
      expect(
        document.findAllElements('clef-octave-change').single.innerText,
        '1',
      );
      expect(
        document.findAllElements('octave').first.innerText,
        '5', // C4 written under an 8-up clef sounds as C5.
      );
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

  test('per-measure time signatures survive MXL save and load', () async {
    final root = await Directory.systemTemp.createTemp(
      'rookie-meter-roundtrip-',
    );
    addTearDown(() => root.delete(recursive: true));
    final service = CompositionStorageService(
      documentsDirectory: () async => root,
    );
    const events = [
      RawNoteEvent(
        startTimeMs: 0,
        endTimeMs: 500,
        frequencyHz: 246.94,
        midiPitch: 59,
        confidence: 1,
      ),
      RawNoteEvent(
        startTimeMs: 500,
        endTimeMs: 2500,
        frequencyHz: 392,
        midiPitch: 67,
        confidence: 1,
      ),
    ];
    const templates = [
      Measure(index: 0, beatsPerMeasure: 1, beatUnit: 4),
      Measure(index: 1, beatsPerMeasure: 4, beatUnit: 4),
    ];
    final measures = const MeasureBuilder().build(
      events,
      120,
      4,
      measureTemplates: templates,
      addTrailingMeasure: false,
    );
    final composition = Composition(
      title: 'Pickup',
      clef: ClefType.treble,
      measures: measures,
    );

    final saved = await service.save(
      composition: composition,
      rawEvents: events,
    );
    final archive = ZipDecoder().decodeBytes(
      await File(saved.path).readAsBytes(),
    );
    final document = XmlDocument.parse(
      utf8.decode(archive.findFile('score.musicxml')!.content),
    );
    expect(document.findAllElements('beats').map((value) => value.innerText), [
      '1',
      '4',
    ]);

    final loaded = await service.load(saved.path);
    expect(loaded.composition.measures.first.beatsPerMeasure, 1);
    expect(loaded.composition.measures[1].beatsPerMeasure, 4);
    expect(loaded.composition.measureStartTick(1), 480);
  });

  test('imports a standard uncompressed MusicXML score', () async {
    final root = await Directory.systemTemp.createTemp('rookie-xml-import-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/external.musicxml');
    await file.writeAsString(_externalMusicXml);
    final service = CompositionStorageService(
      documentsDirectory: () async => root,
    );

    final imported = await service.importFile(file.path);

    expect(imported.composition.title, 'Imported Waltz');
    expect(imported.composition.clef, ClefType.bass);
    expect(imported.composition.keySignature, KeySignature.fMajor);
    expect(imported.composition.beatsPerMeasure, 3);
    expect(imported.composition.beatUnit, 4);
    expect(imported.composition.tempoBpm, 90);
    expect(imported.rawEvents, hasLength(4));
    expect(imported.rawEvents.first.midiPitch, 58);
    expect(imported.rawEvents[1].isRest, isTrue);
    expect(imported.rawEvents[2].accidental, NoteAccidental.natural);
    expect(imported.rawEvents[2].tieToNext, isTrue);
  });

  test('imports a transposing clef without moving its written notes', () async {
    final root = await Directory.systemTemp.createTemp(
      'rookie-octave-clef-import-',
    );
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/tenor.musicxml');
    await file.writeAsString(_octaveClefMusicXml);
    final service = CompositionStorageService(
      documentsDirectory: () async => root,
    );

    final imported = await service.importFile(file.path);

    expect(imported.composition.clef, ClefType.treble);
    expect(imported.composition.octaveRange, OctaveRange.octaveDown);
    expect(imported.rawEvents.first.midiPitch, 59); // B3 sounding.
    expect(
      imported.composition.measures.first.notes.single.midiPitch,
      71, // B4 written for an 8-down clef.
    );
    expect(imported.composition.measures, hasLength(2));
    expect(imported.composition.measures.first.beatsPerMeasure, 1);
    expect(imported.composition.measures.first.beatUnit, 4);
    expect(imported.composition.measures[1].beatsPerMeasure, 4);
    expect(imported.composition.measureStartTick(1), 480);
  });

  test(
    'finds and imports the root score in a standard MXL container',
    () async {
      final root = await Directory.systemTemp.createTemp('rookie-mxl-import-');
      addTearDown(() => root.delete(recursive: true));
      final archive = Archive()
        ..addFile(
          ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="scores/main.musicxml"/></rootfiles>
</container>'''),
        )
        ..addFile(
          ArchiveFile.string('scores/main.musicxml', _externalMusicXml),
        );
      final file = File('${root.path}/external.mxl');
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
      final service = CompositionStorageService(
        documentsDirectory: () async => root,
      );

      final imported = await service.importFile(file.path);

      expect(imported.composition.title, 'Imported Waltz');
      expect(imported.rawEvents.first.midiPitch, 58);
    },
  );
}

const _externalMusicXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <work><work-title>Imported Waltz</work-title></work>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <key><fifths>-1</fifths></key>
        <time><beats>3</beats><beat-type>4</beat-type></time>
        <clef><sign>F</sign><line>4</line></clef>
      </attributes>
      <direction><sound tempo="90"/></direction>
      <note><pitch><step>B</step><alter>-1</alter><octave>3</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type></note>
      <note><rest/><duration>1</duration><voice>1</voice><type>eighth</type></note>
      <note><pitch><step>B</step><octave>3</octave></pitch><duration>3</duration><voice>1</voice><type>quarter</type><dot/><accidental>natural</accidental><tie type="start"/></note>
    </measure>
    <measure number="2">
      <note><pitch><step>B</step><octave>3</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><tie type="stop"/></note>
    </measure>
  </part>
</score-partwise>''';

const _octaveClefMusicXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Tenor</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>
      </attributes>
      <note><pitch><step>B</step><octave>3</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type></note>
    </measure>
    <measure number="2">
      <note><pitch><step>G</step><octave>3</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>
    </measure>
  </part>
</score-partwise>''';
