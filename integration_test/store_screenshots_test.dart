import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sheet_music_rookie/main.dart' as app;
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture real store screens with a local sample score', (
    tester,
  ) async {
    final events = <RawNoteEvent>[];
    // Original, deterministic C-major exercise, not microphone simulation.
    const pitches = [60, 64, 67, 64, 62, 65, 69, 67, 64, 62, 60, 60];
    for (var i = 0; i < pitches.length; i++) {
      events.add(
        RawNoteEvent(
          startTimeMs: i * 500,
          endTimeMs: (i + 1) * 500,
          frequencyHz: (440 * math.pow(2, (pitches[i] - 69) / 12)).toDouble(),
          midiPitch: pitches[i],
          confidence: .98,
        ),
      );
    }
    final composition = Composition(
      title: 'Morning Melody',
      clef: ClefType.treble,
      tempoBpm: 120,
      measures: const MeasureBuilder().build(events, 120, 4),
    );
    final storage = CompositionStorageService();
    final saved = await storage.listSaved();
    final existing = saved.where(
      (s) => s.composition.title == composition.title,
    );
    await storage.save(
      composition: composition,
      rawEvents: events,
      existingPath: existing.isEmpty ? null : existing.first.path,
    );
    app.main();
    await tester.pumpAndSettle();
    await tester.runAsync(() => precacheImage(
      const AssetImage('assets/app_icon/app-store-1024.png'),
      tester.element(find.text('Sheet Music Rookie')),
    ));
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      const only = String.fromEnvironment('CAPTURE_ONLY');
      await tester.pumpAndSettle();
      if (only.isNotEmpty && only != name) return;
      // Native OS capture avoids blank Metal textures in UIKit snapshots.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        const endpoint = String.fromEnvironment(
          'CAPTURE_SERVER',
          defaultValue: 'http://127.0.0.1:8765',
        );
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse('$endpoint/$name'));
          final response = await request.close();
          await response.drain<void>();
          if (response.statusCode != 200) {
            throw StateError('Native capture failed: $name');
          }
        } finally {
          client.close();
        }
      });
    }

    await capture('01_main_menu');
    await tester.tap(find.text('Create'));
    await capture('02_select_clef');
    await tester.tap(find.text('Treble Clef'));
    await capture('03_octave_range');
    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Insert Note'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning Melody').first);
    await capture('04_musical_composition');
    await tester.tap(find.text('120 BPM'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pumpAndSettle();
    await capture('05_tempo_controls');
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Toggle left repeat'));
    await capture('06_note_editing');
    // Shut down through the navigator to release audio/ticker resources.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  });
}
