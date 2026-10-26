import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/music/performance_plan.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/services/practice_service.dart';
import 'package:sheet_music_rookie/services/melody_test_service.dart';
import 'package:xml/xml.dart';

const native =
    '''<museScore version="4.70"><Score><metaTag name="workTitle">Test &amp; canción</metaTag><Part><Staff/></Part><Staff id="1"><Measure><startRepeat/><voice><TimeSig><sigN>2</sigN><sigD>4</sigD></TimeSig><KeySig><concertKey>-1</concertKey></KeySig><Tempo><tempo>2</tempo></Tempo><Rest><durationType>quarter</durationType></Rest><Chord><durationType>quarter</durationType><Lyrics><no>1</no><syllabic>begin</syllabic><text>Señor</text></Lyrics><Note><pitch>70</pitch><tpc>12</tpc></Note></Chord></voice></Measure><Measure><endRepeat>2</endRepeat><voice><Rest><durationType>measure</durationType><duration>1/2</duration></Rest></voice></Measure></Staff></Score></museScore>''';
void main() {
  test('native archive skips style rootfiles and imports notes lyrics meter and repeats', () async {
    final root = await Directory.systemTemp.createTemp('mscz-test');
    addTearDown(() => root.delete(recursive: true));
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="style.mss"/><rootfile full-path="score.mscx"/></rootfiles></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string('style.mss', '<museScore><Style/></museScore>'),
      )
      ..addFile(ArchiveFile.string('score.mscx', native));
    final source = File('${root.path}/song.mscz');
    await source.writeAsBytes(ZipEncoder().encodeBytes(archive));
    final storage = CompositionStorageService(
      documentsDirectory: () async => root,
    );
    final imported = await storage.importFile(source.path);
    expect(imported.composition.title, 'song');
    expect(imported.composition.tempoBpm, 120);
    expect(imported.composition.beatsPerMeasure, 2);
    expect(imported.composition.keySignature.accidentalCount, -1);
    expect(imported.rawEvents.map((e) => e.isRest), [true, false, true]);
    expect(imported.rawEvents[1].midiPitch, 70);
    expect(imported.rawEvents[1].lyrics.single.number, '2');
    expect(imported.rawEvents[1].lyrics.single.text, 'Señor');
    expect(
      PerformancePlan(imported.composition).visits.map((v) => v.sourceIndex),
      [0, 1, 0, 1],
    );
    final saved = await storage.save(
      composition: imported.composition,
      rawEvents: imported.rawEvents,
    );
    final loaded = await storage.load(saved.path);
    expect(loaded.rawEvents[1].lyrics.single.text, 'Señor');
    expect(PerformancePlan(loaded.composition).visits.length, 4);
    expect(await source.readAsBytes(), ZipEncoder().encodeBytes(archive));
  });
  test('uncompressed native files and archive fallback work', () async {
    final root = await Directory.systemTemp.createTemp('mscx-test');
    addTearDown(() => root.delete(recursive: true));
    final storage = CompositionStorageService();
    final file = File('${root.path}/score.mscx');
    await file.writeAsString(native);
    expect((await storage.importFile(file.path)).rawEvents.length, 3);
    final archive = Archive()
      ..addFile(ArchiveFile.string('score.mscx', native));
    final zipped = File('${root.path}/score.mscz');
    await zipped.writeAsBytes(ZipEncoder().encodeBytes(archive));
    expect((await storage.importFile(zipped.path)).rawEvents.length, 3);
    await file.writeAsString(native.replaceFirst('<Rest>', '<Tuplet/><Rest>'));
    await expectLater(storage.importFile(file.path), throwsFormatException);
  });

  final example = Platform.environment['MUSESCORE_EXAMPLE'];
  test(
    'supplied Canto de Ofrendas preserves its melody lyrics and repeat sequence',
    () async {
      final root = await Directory.systemTemp.createTemp('mscz-example');
      addTearDown(() => root.delete(recursive: true));
      final storage = CompositionStorageService(
        documentsDirectory: () async => root,
      );
      final imported = await storage.importFile(example!);
      final archive = ZipDecoder().decodeBytes(
        await File(example).readAsBytes(),
      );
      final nativeFile = archive.files.firstWhere(
        (f) => f.name.endsWith('.mscx'),
      );
      final xml = XmlDocument.parse(utf8.decode(nativeFile.content));
      final staff = xml.rootElement
          .getElement('Score')!
          .findElements('Staff')
          .first;
      expect(imported.composition.measures.length, 82);
      expect(imported.composition.tempoBpm, 140);
      expect(
        imported.rawEvents.where((e) => !e.isRest).length,
        staff.findAllElements('Chord').length,
      );
      expect(
        imported.rawEvents.expand((e) => e.lyrics).length,
        staff.findAllElements('Lyrics').length,
      );
      final plan = PerformancePlan(imported.composition);
      expect(plan.visits.length, 125);
      final practice = PracticeSession(
        imported.composition,
        pitchStabilityMs: 70,
      );
      expect(
        practice.targets.length,
        greaterThan(imported.rawEvents.where((e) => !e.isRest).length),
      );
      final session = MelodyTestSession(imported.composition);
      expect(
        session.plan.visits.map((v) => v.sourceIndex),
        plan.visits.map((v) => v.sourceIndex),
      );
      final saved = await storage.save(
        composition: imported.composition,
        rawEvents: imported.rawEvents,
      );
      expect(
        PerformancePlan((await storage.load(saved.path)).composition)
            .visits
            .length,
        125,
      );
      // ignore: avoid_print
      print(
        'Verified 82 measures, ${imported.rawEvents.length} note/rest events, ${imported.rawEvents.expand((e) => e.lyrics).length} lyric entries, 125 performance visits.',
      );
    },
    skip: example == null
        ? 'Set MUSESCORE_EXAMPLE to a local MSCZ path.'
        : false,
  );
}
