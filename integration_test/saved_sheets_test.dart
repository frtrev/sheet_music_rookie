import 'dart:io';

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
  testWidgets('Sheets plays, stops, opens and removes saved sheets', (
    tester,
  ) async {
    final storage = CompositionStorageService();
    final existing = await storage.listSaved();
    final saved = <SavedComposition>[];
    const names = ['Sheets Manager Alpha', 'Sheets Manager Beta'];
    final events = [
      for (var i = 0; i < 4; i++)
        RawNoteEvent(
          startTimeMs: i * 4000,
          endTimeMs: (i + 1) * 4000,
          frequencyHz: 261.6,
          midiPitch: 60 + i,
          confidence: 1,
        ),
    ];
    for (final name in names) {
      final prior = existing.where((item) => item.composition.title == name);
      saved.add(
        await storage.save(
          composition: Composition(
            title: name,
            clef: ClefType.treble,
            tempoBpm: 60,
            measures: const MeasureBuilder().build(
              events,
              60,
              4,
              addTrailingMeasure: false,
            ),
          ),
          rawEvents: events,
          existingPath: prior.isEmpty ? null : prior.first.path,
        ),
      );
    }
    app.main();
    await tester.pumpAndSettle();
    Future<void> action(String tooltip) async {
      final button = find.byTooltip(tooltip);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    }

    await tester.tap(find.text('Sheets'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Share ${names.first}'), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsWidgets);
    await action('Play ${names.first}');
    await Future<void>.delayed(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byTooltip('Stop ${names.first}'), findsOneWidget);
    await action('Play ${names.last}');
    expect(find.byTooltip('Play ${names.first}'), findsOneWidget);
    expect(find.byTooltip('Stop ${names.last}'), findsOneWidget);
    await action('Stop ${names.last}');
    expect(find.byTooltip('Play ${names.last}'), findsOneWidget);
    await action('Remove ${names.first}');
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(await File(saved.first.path).exists(), isTrue);
    await action('Play ${names.first}');
    await action('Remove ${names.first}');
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(await File(saved.first.path).exists(), isFalse);
    expect(await File(saved.last.path).exists(), isTrue);
    expect(find.text(names.first), findsNothing);
    await tester.ensureVisible(find.text(names.last));
    await tester.tap(find.text(names.last));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScoreView>(find.byType(ScoreView)).composition.title,
      names.last,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheets'));
    await tester.pumpAndSettle();
    expect(find.text(names.first), findsNothing);
    await action('Remove ${names.last}');
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(await File(saved.last.path).exists(), isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Create'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
