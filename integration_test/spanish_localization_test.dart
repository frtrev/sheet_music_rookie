import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sheet_music_rookie/main.dart' as app;
import 'package:sheet_music_rookie/models/app_language.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/note_lyric.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/services/settings_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Spanish settings, sheets, lyrics and measure marks work on iPhone',
    (tester) async {
      final settings = SettingsService();
      final previous = await settings.loadAppLanguage();
      addTearDown(() => settings.saveAppLanguage(previous));
      await settings.saveAppLanguage(AppLanguage.spanish);
      final storage = CompositionStorageService();
      const title = 'Mi partitura de prueba';
      final existing = (await storage.listSaved()).where(
        (item) => item.composition.title == title,
      );
      final events = [
        RawNoteEvent(
          startTimeMs: 0,
          endTimeMs: 500,
          frequencyHz: 261.6,
          midiPitch: 60,
          confidence: 1,
          lyrics: [NoteLyric.fromText('1', 'Mi canción')],
        ),
      ];
      final saved = await storage.save(
        composition: Composition(
          title: title,
          clef: ClefType.treble,
          measures: const MeasureBuilder().build(events, 120, 4),
        ),
        rawEvents: events,
        existingPath: existing.isEmpty ? null : existing.first.path,
      );
      addTearDown(() => storage.removeSaved(saved));
      app.main();
      await tester.pumpAndSettle();
      expect(find.text('Sheet Music Rookie'), findsOneWidget);
      expect(find.text('Partituras para Novatos'), findsOneWidget);
      Future<void> language(String settingsText, String choice) async {
        await tester.ensureVisible(find.text(settingsText));
        await tester.tap(find.text(settingsText));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<AppLanguage>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }

      await language('Ajustes', 'English');
      expect(find.text('Sheets'), findsOneWidget);
      expect(await settings.loadAppLanguage(), AppLanguage.english);
      await language('Settings', 'Español');
      expect(find.text('Partituras'), findsOneWidget);
      await tester.ensureVisible(find.text('Partituras'));
      await tester.tap(find.text('Partituras'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproducir $title'), findsOneWidget);
      expect(find.byTooltip('Compartir $title'), findsOneWidget);
      expect(find.byTooltip('Eliminar $title'), findsOneWidget);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Editar letra'));
      await tester.tap(find.byTooltip('Editar letra'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('inline-lyric-text'));
      expect(tester.widget<TextField>(field).decoration!.hintText, 'Línea 1');
      await tester.enterText(field, 'Letra en español');
      await tester.tap(find.byTooltip('Siguiente línea de letra').first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).decoration!.hintText, 'Línea 2');
      await tester.enterText(field, 'Segunda letra');
      await tester.tap(find.byTooltip('Terminar de editar la letra'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('left-volta')));
      await tester.tap(find.byKey(const ValueKey('left-volta')));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(
          'Casilla del lado izquierdo: 1 (ciclo 1, 2, 3, ninguna)',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('Guardar partitura'));
      await tester.tap(find.byTooltip('Guardar partitura'));
      await tester.pumpAndSettle();
      final loaded = await storage.load(saved.path);
      expect(loaded.composition.title, title);
      expect(loaded.rawEvents.first.lyrics.map((lyric) => lyric.text), [
        'Letra en español',
        'Segunda letra',
      ]);
      await tester.tap(find.byTooltip('Atrás'));
      await tester.pumpAndSettle();
      await language('Ajustes', 'English');
      await tester.ensureVisible(find.text('Sheets'));
      await tester.tap(find.text('Sheets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      final reopened = tester.widget<ScoreView>(find.byType(ScoreView));
      expect(reopened.composition.title, title);
      expect(
        reopened.composition.measures.first.notes.first.lyrics.first.text,
        'Letra en español',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
