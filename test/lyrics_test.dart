import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/note_lyric.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';

class _MeasuredLyric extends NoteLyric {
  _MeasuredLyric() : super('<lyric number="1"><text>Melodía</text></lyric>');
  int textReads = 0;
  @override
  String get text {
    textReads++;
    return super.text;
  }
}

void main() {
  test(
    'imports multiple lyric lines and preserves Unicode and XML on save',
    () async {
      final root = await Directory.systemTemp.createTemp('lyrics-test');
      addTearDown(() => root.delete(recursive: true));
      final service = CompositionStorageService(
        documentsDirectory: () async => root,
      );
      final file = File('${root.path}/lyrics.musicxml');
      await file.writeAsString(
        '''<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list><part id="P1"><measure number="1"><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><lyric number="2"><syllabic>single</syllabic><text>paz &amp; fe</text><extend type="start"/></lyric><lyric number="1"><syllabic>begin</syllabic><text>Señor</text></lyric></note></measure></part></score-partwise>''',
      );
      final imported = await service.importFile(file.path);
      final first = imported.composition.measures.first.notes.first;
      expect(first.lyrics.map((l) => l.number), ['2', '1']);
      expect(first.lyrics.first.text, 'paz & fe');
      expect(first.lyrics.last.text, 'Señor');
      final saved = await service.save(
        composition: imported.composition,
        rawEvents: imported.rawEvents,
      );
      final reopened = await service.load(saved.path);
      expect(reopened.rawEvents.first.lyrics.first.xml, first.lyrics.first.xml);
      expect(
        reopened.composition.measures.first.notes.first.lyrics.last.text,
        'Señor',
      );
      final archive = ZipDecoder().decodeBytes(
        await File(saved.path).readAsBytes(),
      );
      final xml = utf8.decode(
        archive.findFile('score.musicxml')!.content as List<int>,
      );
      expect(xml, contains('paz &amp; fe'));
      expect(xml, contains('extend type="start"'));
      final exported = File('${root.path}/export.musicxml');
      await exported.writeAsString(xml);
      expect(
        (await service.importFile(exported.path)).rawEvents.first.lyrics.length,
        2,
      );
    },
  );

  testWidgets(
    'all verse rows fit in a scrollable score and keep cursor alignment',
    (tester) async {
      final events = [
        RawNoteEvent(
          startTimeMs: 0,
          endTimeMs: 2500,
          frequencyHz: 261.63,
          midiPitch: 60,
          confidence: 1,
          lyrics: [
            for (final n in [10, 2, 1, 3, 4, 5, 6])
              NoteLyric('<lyric number="$n"><text>Melodía</text></lyric>'),
          ],
        ),
      ];
      final score = Composition(
        clef: ClefType.treble,
        measures: const MeasureBuilder().build(events, 120, 4),
      );
      expect(
        score.measures
            .expand((m) => m.notes)
            .where((n) => n.lyrics.isNotEmpty)
            .length,
        1,
      );
      expect(ScoreLayout.lyricLines(score), [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '10',
      ]);
      expect(ScoreLayout.height(score), greaterThan(350));
      final note = score.measures.first.notes.first;
      expect(
        ScoreLayout.tickAtX(score, ScoreLayout.noteCenter(score, 0, note).dx),
        0,
      );
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 350,
              child: ScoreView(
                composition: score,
                scrollController: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ScoreView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cursor following reuses lyric measurements and the static score layer',
    (tester) async {
      final lyric = _MeasuredLyric();
      final events = [
        for (var i = 0; i < 80; i++)
          RawNoteEvent(
            startTimeMs: i * 500,
            endTimeMs: (i + 1) * 500,
            frequencyHz: 261.63,
            midiPitch: 60,
            confidence: 1,
            lyrics: [lyric],
          ),
      ];
      final score = Composition(
        clef: ClefType.treble,
        measures: const MeasureBuilder().build(events, 120, 4),
      );
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget view(Duration position) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 350,
            child: ScoreView(
              composition: score,
              scrollController: controller,
              selectedEventIndex: 0,
              showPlaybackCursor: true,
              playbackPosition: position,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(Duration.zero));
      final originalPainter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<ScorePainter>()
          .single;
      final readsAfterLayout = lyric.textReads;
      for (var tick = 0; tick < 30000; tick += 120) {
        ScoreLayout.cursorX(score, tick);
        ScoreLayout.height(score);
      }
      await tester.pumpWidget(view(const Duration(milliseconds: 100)));
      final nextPainter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<ScorePainter>()
          .single;
      expect(nextPainter.shouldRepaint(originalPainter), isFalse);
      expect(
        lyric.textReads,
        readsAfterLayout,
        reason: 'Playback must not remeasure lyrics on each cursor update.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('lyric playback crosses widened measures without a boundary jump', () {
    final events = [
      for (var i = 0; i < 12; i++)
        RawNoteEvent(
          startTimeMs: i * 500,
          endTimeMs: (i + 1) * 500,
          frequencyHz: 261.63,
          midiPitch: 60,
          confidence: 1,
          lyrics: [
            NoteLyric(
              '<lyric number="1"><text>${i < 4 ? 'Longer lyric phrase' : 'Se'}</text></lyric>',
            ),
          ],
        ),
    ];
    final score = Composition(
      clef: ClefType.treble,
      measures: const MeasureBuilder().build(events, 120, 4),
    );
    expect(
      ScoreLayout.widthFor(score, 0),
      greaterThan(ScoreLayout.widthFor(score, 1)),
    );
    for (final measure in score.measures) {
      for (final note in measure.notes) {
        final tick = score.measureStartTick(measure.index) + note.startTick;
        final x = ScoreLayout.noteCenter(score, measure.index, note).dx;
        expect(ScoreLayout.playbackCursorX(score, tick), closeTo(x, .001));
        if (tick > 0) {
          expect(
            x - ScoreLayout.playbackCursorX(score, tick - 1),
            inInclusiveRange(0, 2),
          );
        }
      }
    }
    var offset = 0.0;
    var previous = ScoreLayout.playbackCursorX(score, 0);
    for (var tick = 1; tick < 5760; tick++) {
      final x = ScoreLayout.playbackCursorX(score, tick);
      expect(x - previous, inInclusiveRange(0, 2));
      offset =
          ScoreLayout.scrollOffsetToFollowCursor(
            cursorX: x,
            currentOffset: offset,
            viewportWidth: 400,
            maxScrollExtent: 10000,
            followFraction: .4,
          ) ??
          offset;
      if (x >= 160) expect(x - offset, closeTo(160, .001));
      previous = x;
    }
  });

  final example = Platform.environment['LYRIC_EXAMPLE'];
  test('user supplied MXL lyrics survive save and reopen', () async {
    final root = await Directory.systemTemp.createTemp('lyrics-example');
    addTearDown(() => root.delete(recursive: true));
    final service = CompositionStorageService(
      documentsDirectory: () async => root,
    );
    final imported = await service.importFile(example!);
    final lyrics = imported.rawEvents.expand((e) => e.lyrics).toList();
    expect(lyrics, isNotEmpty);
    expect(lyrics.map((l) => l.text).join(' '), contains('ñor'));
    final saved = await service.save(
      composition: imported.composition,
      rawEvents: imported.rawEvents,
    );
    final reopened = await service.load(saved.path);
    expect(
      reopened.rawEvents.expand((e) => e.lyrics).map((l) => l.xml).toList(),
      lyrics.map((l) => l.xml).toList(),
    );
    // ignore: avoid_print
    print(
      'Verified ${imported.rawEvents.length} notes/rests and ${lyrics.length} lyric entries in supplied MXL.',
    );
  }, skip: example == null ? 'Set LYRIC_EXAMPLE to a local MXL path.' : false);
}
