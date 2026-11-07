import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/note_lyric.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';
import 'package:sheet_music_rookie/transcription/transcription_engine.dart';

class _SilentMicrophone implements MicrophoneService {
  @override
  Stream<AudioFrame> get frames => const Stream.empty();
  @override
  Future<bool> start() async => false;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

TranscriptionEngine engineWithLyrics() {
  final events = [
    const RawNoteEvent(
      startTimeMs: 0,
      endTimeMs: 500,
      frequencyHz: 261.6,
      midiPitch: 60,
      confidence: 1,
      lyrics: [
        NoteLyric(
          '<lyric number="1" name="verse" xml:lang="es"><syllabic>begin</syllabic><text>Hola</text><extend type="start"/></lyric>',
        ),
        NoteLyric('<lyric number="2"><text>World</text></lyric>'),
      ],
    ),
    const RawNoteEvent(
      startTimeMs: 500,
      endTimeMs: 1000,
      frequencyHz: 293.7,
      midiPitch: 62,
      confidence: 1,
    ),
  ];
  return TranscriptionEngine(
    clef: ClefType.treble,
    octaveRange: OctaveRange.standard,
    microphone: _SilentMicrophone(),
    initialEvents: events,
    initialComposition: Composition(
      clef: ClefType.treble,
      measures: const MeasureBuilder().build(events, 120, 4),
    ),
  );
}

Future<void> showScore(
  WidgetTester tester,
  TranscriptionEngine engine,
  GlobalKey<ScoreViewState> key,
) async {
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 350,
          child: ValueListenableBuilder<Composition>(
            valueListenable: engine.composition,
            builder: (_, score, _) => ScoreView(
              key: key,
              composition: score,
              scrollController: scroll,
              selectedTick: 0,
              onLyricChanged: engine.setLyricAtTick,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'lyric edits preserve metadata, support undo/redo, deletion and MXL reopen',
    () async {
      final engine = engineWithLyrics();
      addTearDown(engine.dispose);
      engine.setLyricAtTick(0, '1', 'Señor & luz <paz>');
      final lyric = engine.rawEvents.first.lyrics.first;
      expect(lyric.text, 'Señor & luz <paz>');
      expect(lyric.syllabic, 'begin');
      expect(lyric.extendsNote, isTrue);
      expect(lyric.element.getAttribute('name'), 'verse');
      expect(lyric.element.getAttribute('xml:lang'), 'es');
      expect(engine.rawEvents.first.lyrics.last.text, 'World');
      engine.undo();
      expect(engine.rawEvents.first.lyrics.first.text, 'Hola');
      engine.redo();
      expect(engine.rawEvents.first.lyrics.first.text, 'Señor & luz <paz>');
      engine.setLyricAtTick(0, '4', 'Fourth verse');
      engine.setLyricAtTick(0, '2', '');
      expect(engine.rawEvents.first.lyrics.map((l) => l.number), ['1', '4']);
      final folder = await Directory.systemTemp.createTemp('edited-lyrics');
      addTearDown(() => folder.delete(recursive: true));
      final storage = CompositionStorageService(
        documentsDirectory: () async => folder,
      );
      final saved = await storage.save(
        composition: engine.composition.value,
        rawEvents: engine.rawEvents,
      );
      final loaded = await storage.load(saved.path);
      expect(loaded.rawEvents.first.lyrics.map((l) => l.text), [
        'Señor & luz <paz>',
        'Fourth verse',
      ]);
    },
  );

  testWidgets('double tapping the painted lyric opens its inline text', (
    tester,
  ) async {
    final engine = engineWithLyrics();
    addTearDown(engine.dispose);
    final key = GlobalKey<ScoreViewState>();
    await showScore(tester, engine, key);
    final rect = ScoreLayout.lyricTextBounds(
      engine.composition.value,
      0,
      0,
      engine.composition.value.measures.first.notes.first.lyrics.first,
    );
    final origin = tester.getTopLeft(find.byType(ScoreView));
    await tester.tapAt(origin + rect.center);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tapAt(origin + rect.center);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('inline-lyric-text'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'Hola');
    await tester.enterText(field, 'Buenos días');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(engine.rawEvents.first.lyrics.first.text, 'Buenos días');
    expect(field, findsNothing);
  });

  testWidgets('selected-note entry and keyboard arrows edit all four lines', (
    tester,
  ) async {
    final engine = engineWithLyrics();
    addTearDown(engine.dispose);
    final key = GlobalKey<ScoreViewState>();
    await showScore(tester, engine, key);
    await key.currentState!.startLyricEditing(480);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('inline-lyric-text'));
    await tester.enterText(field, 'First');
    for (final text in ['Second', 'Third', 'Fourth']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.enterText(field, text);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'Fourth');
    for (final text in ['Third', 'Second', 'First']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, text);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(engine.rawEvents[1].lyrics.map((l) => l.text), [
      'First',
      'Second',
      'Third',
      'Fourth',
    ]);
    expect(engine.rawEvents.first.lyrics.first.text, 'Hola');
  });

  testWidgets('onscreen arrows keep editing and Escape cancels pending text', (
    tester,
  ) async {
    final engine = engineWithLyrics();
    addTearDown(engine.dispose);
    final key = GlobalKey<ScoreViewState>();
    await showScore(tester, engine, key);
    await key.currentState!.startLyricEditing(0);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('inline-lyric-text'));
    await tester.enterText(field, 'Changed');
    await tester.tap(find.byTooltip('Next lyric line'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'World');
    await tester.enterText(field, 'Discard this');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(engine.rawEvents.first.lyrics.map((l) => l.text), [
      'Changed',
      'World',
    ]);
  });
}
