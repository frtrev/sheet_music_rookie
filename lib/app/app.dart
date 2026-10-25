import 'dart:async';

import 'app_theme.dart';

import 'package:flutter/material.dart';

import '../screens/score_editor_screen.dart';
import '../screens/home_screen.dart';
import '../services/composition_storage_service.dart';
import '../services/incoming_file_service.dart';

class SheetMusicRookieApp extends StatefulWidget {
  const SheetMusicRookieApp({super.key});

  @override
  State<SheetMusicRookieApp> createState() => _SheetMusicRookieAppState();
}

class _SheetMusicRookieAppState extends State<SheetMusicRookieApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey();
  final IncomingFileService _incomingFiles = IncomingFileService();
  final CompositionStorageService _storage = CompositionStorageService();
  final List<String> _pendingFiles = [];
  StreamSubscription<String>? _fileSubscription;
  bool _openingFile = false;

  @override
  void initState() {
    super.initState();
    _fileSubscription = _incomingFiles.files.listen(_queueFile);
    unawaited(_incomingFiles.initialize());
  }

  void _queueFile(String path) {
    _pendingFiles.add(path);
    unawaited(_openNextFile());
  }

  Future<void> _openNextFile() async {
    if (_openingFile || _pendingFiles.isEmpty) return;
    _openingFile = true;
    final path = _pendingFiles.removeAt(0);
    try {
      final imported = await _storage.importFile(path);
      if (!mounted) return;
      _showImportedComposition(imported);
    } on Object {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('This MusicXML file could not be opened.'),
        ),
      );
    } finally {
      _openingFile = false;
      if (_pendingFiles.isNotEmpty) unawaited(_openNextFile());
    }
  }

  void _showImportedComposition(SavedComposition imported) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showImportedComposition(imported);
      });
      return;
    }
    unawaited(
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => ScoreEditorScreen(
            clef: imported.composition.clef,
            octaveRange: imported.composition.octaveRange,
            initialComposition: imported.composition,
            initialEvents: imported.rawEvents,
          ),
        ),
        (route) => route.isFirst,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Sheet Music Rookie',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }

  @override
  void dispose() {
    unawaited(_fileSubscription?.cancel());
    unawaited(_incomingFiles.dispose());
    super.dispose();
  }
}
