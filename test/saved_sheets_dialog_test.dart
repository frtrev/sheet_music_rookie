import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/services/score_playback_service.dart';
import 'package:sheet_music_rookie/widgets/saved_sheets_dialog.dart';

class _Playback implements ScorePlaybackService {
  final played = <Composition>[];
  int stops = 0;
  bool disposed = false;
  Completer<bool>? preparing;
  @override
  VoidCallback? onComplete;
  @override
  Future<bool> play(
    Composition composition, {
    Duration startAt = Duration.zero,
  }) async {
    played.add(composition);
    return preparing == null ? true : preparing!.future;
  }

  @override
  Future<void> stop({bool resetPosition = false}) async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage extends CompositionStorageService {
  final removed = <SavedComposition>[];
  @override
  Future<void> removeSaved(SavedComposition item) async {
    removed.add(item);
  }
}

SavedComposition sheet(String name) => SavedComposition(
  path: '/tmp/$name.mxl',
  composition: Composition(title: name, clef: ClefType.treble),
  rawEvents: const [],
  modifiedAt: DateTime(2026, 11, 7, 12),
);

Future<void> _showSheets(
  WidgetTester tester,
  List<SavedComposition> sheets,
  _Playback playback, {
  CompositionStorageService? storage,
  void Function(SavedComposition?)? onClosed,
  void Function(SavedComposition)? onShare,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            child: const Text('Launch'),
            onPressed: () async {
              final selected = await showDialog<SavedComposition>(
                context: context,
                builder: (_) => SavedSheetsDialog(
                  sheets: sheets,
                  storage: storage ?? CompositionStorageService(),
                  playback: playback,
                  onShare: (_, item) async => onShare?.call(item),
                ),
              );
              onClosed?.call(selected);
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launch'));
  await tester.pumpAndSettle();
}

void main() {
  test('removeSaved deletes only the chosen saved file', () async {
    final folder = await Directory.systemTemp.createTemp('sheets-manager');
    addTearDown(() => folder.delete(recursive: true));
    final storage = CompositionStorageService(
      documentsDirectory: () async => folder,
    );
    final items = <SavedComposition>[];
    for (final name in ['First', 'Second']) {
      items.add(
        await storage.save(
          composition: Composition(title: name, clef: ClefType.treble),
          rawEvents: const [],
        ),
      );
    }
    await storage.removeSaved(items.first);
    expect(await File(items.first.path).exists(), isFalse);
    expect(await File(items.last.path).exists(), isTrue);
    expect((await storage.listSaved()).map((item) => item.composition.title), [
      'Second',
    ]);
  });

  testWidgets(
    'play toggles to stop, switches sheets, and resets on completion',
    (tester) async {
      final playback = _Playback();
      final first = sheet('First');
      final second = sheet('Second');
      await _showSheets(tester, [first, second], playback);
      await tester.tap(find.byTooltip('Play First'));
      await tester.pumpAndSettle();
      expect(playback.played, [first.composition]);
      expect(find.byTooltip('Stop First'), findsOneWidget);
      await tester.tap(find.byTooltip('Play Second'));
      await tester.pumpAndSettle();
      expect(playback.played, [first.composition, second.composition]);
      expect(find.byTooltip('Play First'), findsOneWidget);
      expect(find.byTooltip('Stop Second'), findsOneWidget);
      playback.onComplete!();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Play Second'), findsOneWidget);
      await tester.tap(find.byTooltip('Play First'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stop First'));
      await tester.pumpAndSettle();
      expect(playback.played, hasLength(3));
      expect(find.byTooltip('Play First'), findsOneWidget);
      expect(playback.stops, 4);
    },
  );

  testWidgets(
    'stop while preparing keeps playback off when preparation finishes',
    (tester) async {
      final playback = _Playback()..preparing = Completer<bool>();
      await _showSheets(tester, [sheet('First')], playback);
      await tester.tap(find.byTooltip('Play First'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stop First'));
      await tester.pumpAndSettle();
      playback.preparing!.complete(false);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Play First'), findsOneWidget);
      expect(find.text('This sheet has no playable notes.'), findsNothing);
    },
  );

  testWidgets(
    'tap still opens the sheet and stops audio; share leaves list open',
    (tester) async {
      final playback = _Playback();
      final item = sheet('First');
      SavedComposition? shared;
      SavedComposition? opened;
      await _showSheets(
        tester,
        [item],
        playback,
        onShare: (item) => shared = item,
        onClosed: (item) => opened = item,
      );
      await tester.tap(find.byTooltip('Share First'));
      await tester.pumpAndSettle();
      expect(shared, same(item));
      expect(opened, isNull);
      expect(find.text('Sheets'), findsOneWidget);
      await tester.tap(find.byTooltip('Play First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      expect(opened, same(item));
      expect(playback.disposed, isTrue);
      expect(playback.stops, 2);
    },
  );

  testWidgets(
    'remove cancels or deletes only that sheet, including active playback',
    (tester) async {
      final storage = _Storage();
      final items = [sheet('First'), sheet('Second')];
      final playback = _Playback();
      await _showSheets(tester, items, playback, storage: storage);
      await tester.tap(find.byTooltip('Remove First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(storage.removed, isEmpty);
      await tester.tap(find.byTooltip('Play First'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(storage.removed, [items.first]);
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove Second'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('No saved sheets yet.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(playback.disposed, isTrue);
    },
  );

  testWidgets(
    'narrow list retains note, three actions and Cancel without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final title = 'A very long sheet title that needs to wrap neatly';
      final playback = _Playback();
      await _showSheets(tester, [sheet(title)], playback);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.byTooltip('Play $title'), findsOneWidget);
      expect(find.byTooltip('Share $title'), findsOneWidget);
      expect(find.byTooltip('Remove $title'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(playback.disposed, isTrue);
      expect(find.text('Sheets'), findsNothing);
    },
  );
}
