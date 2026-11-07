import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sheet_music_rookie/main.dart' as app;
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('edit lyrics from toolbar and double tap, then save and reopen', (
    tester,
  ) async {
    const events = [
      RawNoteEvent(
        startTimeMs: 0,
        endTimeMs: 500,
        frequencyHz: 261.6,
        midiPitch: 60,
        confidence: 1,
      ),
      RawNoteEvent(
        startTimeMs: 500,
        endTimeMs: 1000,
        frequencyHz: 293.7,
        midiPitch: 62,
        confidence: 1,
      ),
    ];
    final storage = CompositionStorageService();
    final items = await storage.listSaved();
    final existing = items.where(
      (item) => item.composition.title == 'Lyric Editing Check',
    );
    final saved = await storage.save(
      composition: Composition(
        title: 'Lyric Editing Check',
        clef: ClefType.treble,
        measures: const MeasureBuilder().build(events, 120, 4),
      ),
      rawEvents: events,
      existingPath: existing.isEmpty ? null : existing.first.path,
    );
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyric Editing Check'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Edit lyrics'));
    await tester.tap(find.byTooltip('Edit lyrics'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('inline-lyric-text'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'First verse');
    await tester.ensureVisible(find.byTooltip('Next lyric line').last);
    await tester.tap(find.byTooltip('Next lyric line').last);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Second verse');
    await tester.tap(find.byTooltip('Finish lyric editing'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Save Composition'));
    await tester.tap(find.byTooltip('Save Composition'));
    await tester.pumpAndSettle();
    expect(
      (await storage.load(saved.path)).rawEvents.first.lyrics
          .map((l) => l.text),
      ['First verse', 'Second verse'],
    );

    await tester.ensureVisible(find.byType(ScoreView));
    await tester.pumpAndSettle();
    final view = tester.widget<ScoreView>(find.byType(ScoreView));
    final note = view.composition.measures.first.notes.first;
    final rect = ScoreLayout.lyricTextBounds(
      view.composition,
      0,
      0,
      note.lyrics.last,
    );
    final scorePaint = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ScorePainter,
    );
    final verticalScroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ScoreView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    verticalScroll.position.jumpTo(verticalScroll.position.maxScrollExtent);
    view.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    final point = tester.getTopLeft(scorePaint) + rect.center;
    await tester.tapAt(point);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'Second verse');
    await tester.enterText(field, 'Edited second verse');
    // Saving directly must commit pending inline input before serializing.
    await tester.ensureVisible(find.byTooltip('Save Composition'));
    await tester.tap(find.byTooltip('Save Composition'));
    await tester.pumpAndSettle();
    expect(
      (await storage.load(saved.path)).rawEvents.first.lyrics
          .map((l) => l.text),
      ['First verse', 'Edited second verse'],
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyric Editing Check'));
    await tester.pumpAndSettle();
    final reopened = tester.widget<ScoreView>(find.byType(ScoreView));
    expect(
      reopened.composition.measures.first.notes.first.lyrics.last.text,
      'Edited second verse',
    );
  });
}
