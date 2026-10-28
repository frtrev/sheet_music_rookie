import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/services/musescore_import.dart';
import 'package:xml/xml.dart';

void main() {
  for (final clef in [ClefType.alto, ClefType.tenor]) {
    test('${clef.label} places middle C on its clef line', () {
      expect(ScoreLayout.staffStep(clef, 60), (clef.musicXmlLine - 1) * 2);
      expect(ScoreLayout.staffStep(clef, clef.bottomLineMidi), 0);
      expect(
        ScoreLayout.staffStep(clef, 72),
        ScoreLayout.staffStep(clef, 60) + 7,
      );
    });

    test('${clef.label} imports and survives MusicXML and app save', () async {
      final root = await Directory.systemTemp.createTemp('c-clef-test-');
      addTearDown(() => root.delete(recursive: true));
      final service = CompositionStorageService(
        documentsDirectory: () async => root,
      );
      final source = File('${root.path}/source.musicxml');
      await source.writeAsString(
        '''<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Melody</part-name></score-part></part-list><part id="P1"><measure number="1"><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>C</sign><line>${clef.musicXmlLine}</line></clef></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note></measure></part></score-partwise>''',
      );
      final imported = await service.importFile(source.path);
      expect(imported.composition.clef, clef);
      expect(imported.rawEvents.single.midiPitch, 60);
      final saved = await service.save(
        composition: imported.composition,
        rawEvents: imported.rawEvents,
      );
      expect((await service.load(saved.path)).composition.clef, clef);
      final archive = ZipDecoder().decodeBytes(
        await File(saved.path).readAsBytes(),
      );
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile('score.musicxml')!.content),
      );
      expect(xml.findAllElements('sign').single.innerText, 'C');
      expect(
        xml.findAllElements('line').single.innerText,
        '${clef.musicXmlLine}',
      );
      final exported = File('${root.path}/exported.musicxml');
      await exported.writeAsString(xml.toXmlString());
      final reimported = await service.importFile(exported.path);
      expect(reimported.composition.clef, clef);
      expect(reimported.rawEvents.single.midiPitch, 60);
    });

    test('${clef.label} converts native MuseScore C clefs', () {
      final xml = XmlDocument.parse(
        '''<museScore version="4.0"><Score><Part><Staff><defaultClef>C${clef.musicXmlLine}</defaultClef></Staff></Part><Staff id="1"><Measure><voice><Clef><concertClefType>C${clef.musicXmlLine}</concertClefType></Clef><Chord><durationType>quarter</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord></voice></Measure></Staff></Score></museScore>''',
      );
      final converted = XmlDocument.parse(museScoreToMusicXml(xml));
      expect(converted.findAllElements('sign').single.innerText, 'C');
      expect(
        converted.findAllElements('line').single.innerText,
        '${clef.musicXmlLine}',
      );
      expect(converted.findAllElements('octave').single.innerText, '4');
    });
  }
}
