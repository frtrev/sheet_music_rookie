import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sheet_music_rookie/main.dart' as app;
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/services/settings_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('speaker toggles and persists when reopening the editor', (
    tester,
  ) async {
    final settings = SettingsService();
    await settings.saveNoteTapPlayback(true);
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
      (item) => item.composition.title == 'Tapped Note Playback Check',
    );
    await storage.save(
      composition: Composition(
        title: 'Tapped Note Playback Check',
        clef: ClefType.treble,
        measures: const MeasureBuilder().build(events, 120, 4),
      ),
      rawEvents: events,
      existingPath: existing.isEmpty ? null : existing.first.path,
    );
    app.main();
    await tester.pumpAndSettle();
    Future<void> open() async {
      await tester.tap(find.text('Sheets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tapped Note Playback Check'));
      await tester.pumpAndSettle();
    }

    Future<void> tapNote() async {
      await tester.ensureVisible(find.byType(ScoreView));
      await tester.pumpAndSettle();
      final view = tester.widget<ScoreView>(find.byType(ScoreView));
      final paint = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is ScorePainter,
      );
      final note = view.composition.measures.first.notes.first;
      await tester.tapAt(
        tester.getTopLeft(paint) +
            ScoreLayout.noteCenter(view.composition, 0, note),
      );
      await tester.pumpAndSettle();
      // Allow native audio rendering to finish before the next interaction.
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.byTooltip('Mute tapped notes'), findsOneWidget);
    await tapNote();
    await tester.ensureVisible(find.byTooltip('Mute tapped notes'));
    await tester.tap(find.byTooltip('Mute tapped notes'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(await settings.loadNoteTapPlayback(), isFalse);
    await tapNote();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await open();
    expect(find.byTooltip('Play tapped notes'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Play tapped notes'));
    await tester.tap(find.byTooltip('Play tapped notes'));
    await tester.pumpAndSettle();
    expect(await settings.loadNoteTapPlayback(), isTrue);
    await tapNote();
  });
}
