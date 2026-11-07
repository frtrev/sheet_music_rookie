import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sheet_music_rookie/main.dart' as app;
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure_marks.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('third row edits selected measure repeats and volta numbers', (
    tester,
  ) async {
    final events = [
      for (var i = 0; i < 5; i++)
        RawNoteEvent(
          startTimeMs: i * 500,
          endTimeMs: (i + 1) * 500,
          frequencyHz: 261.6,
          midiPitch: 60 + i,
          confidence: 1,
        ),
    ];
    final storage = CompositionStorageService();
    final existing = (await storage.listSaved()).where(
      (item) => item.composition.title == 'Measure Marks Check',
    );
    final saved = await storage.save(
      composition: Composition(
        title: 'Measure Marks Check',
        clef: ClefType.treble,
        beatsPerMeasure: 1,
        measures: const MeasureBuilder().build(
          events,
          120,
          1,
          addTrailingMeasure: false,
        ),
      ),
      rawEvents: events,
      existingPath: existing.isEmpty ? null : existing.first.path,
    );
    app.main();
    await tester.pumpAndSettle();
    Future<void> open() async {
      await tester.tap(find.text('Sheets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Measure Marks Check'));
      await tester.pumpAndSettle();
    }

    Composition score() =>
        tester.widget<ScoreView>(find.byType(ScoreView)).composition;
    MeasureMarks marks(int index) =>
        MeasureMarks(score().measures[index].barlines);
    Future<void> press(String name) async {
      final button = find.byKey(ValueKey(name));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    await open();
    await press('left-repeat');
    expect(marks(0).hasRepeat(MeasureEdge.left), isTrue);
    await press('left-repeat');
    expect(marks(0).hasRepeat(MeasureEdge.left), isFalse);
    await press('right-repeat');
    expect(marks(0).hasRepeat(MeasureEdge.right), isTrue);
    for (final expected in ['1', '2', '3', null]) {
      await press('left-volta');
      expect(marks(0).voltaNumber(MeasureEdge.left), expected);
      await press('right-volta');
      expect(marks(0).voltaNumber(MeasureEdge.right), expected);
      expect(marks(0).hasRepeat(MeasureEdge.right), isTrue);
    }
    await press('left-volta');
    await press('right-volta');
    if (find.byTooltip('Mute tapped notes').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.byTooltip('Mute tapped notes'));
      await tester.tap(find.byTooltip('Mute tapped notes'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byType(ScoreView));
    await tester.pumpAndSettle();
    final view = tester.widget<ScoreView>(find.byType(ScoreView));
    final center = ScoreLayout.noteCenter(
      score(),
      1,
      score().measures[1].notes.first,
    );
    view.scrollController!.jumpTo(
      (center.dx - 100).clamp(
        0,
        view.scrollController!.position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
    final paint = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ScorePainter,
    );
    await tester.tapAt(tester.getTopLeft(paint) + center);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.widget<ScoreView>(find.byType(ScoreView)).selectedTick, 480);
    await press('left-repeat');
    expect(marks(1).hasRepeat(MeasureEdge.left), isTrue);
    expect(marks(0).hasRepeat(MeasureEdge.left), isFalse);
    await tester.ensureVisible(find.byTooltip('Undo'));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(marks(1).hasRepeat(MeasureEdge.left), isFalse);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(marks(1).hasRepeat(MeasureEdge.left), isTrue);
    await tester.ensureVisible(find.byTooltip('Save Composition'));
    await tester.tap(find.byTooltip('Save Composition'));
    await tester.pumpAndSettle();
    final loaded = (await storage.load(saved.path)).composition;
    expect(
      MeasureMarks(loaded.measures[0].barlines).voltaNumber(MeasureEdge.left),
      '1',
    );
    expect(
      MeasureMarks(loaded.measures[1].barlines).hasRepeat(MeasureEdge.left),
      isTrue,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await open();
    expect(marks(0).voltaNumber(MeasureEdge.right), '1');
    expect(marks(1).hasRepeat(MeasureEdge.left), isTrue);
  });
}
