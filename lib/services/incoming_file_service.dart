import 'dart:async';

import 'package:flutter/services.dart';

/// Receives file paths delivered by the host platforms through Open With or
/// their share UI. Native code copies temporary/security-scoped files into a
/// readable cache location before sending the path here.
class IncomingFileService {
  static const _channel = MethodChannel('sheet_music_rookie/incoming_file');
  final StreamController<String> _files = StreamController.broadcast();

  Stream<String> get files => _files.stream;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fileOpened' && call.arguments is String) {
        _emit(call.arguments as String);
      }
    });
    try {
      _emit(await _channel.invokeMethod<String>('getInitialFile'));
    } on MissingPluginException {
      // Desktop/unit-test hosts do not install the mobile file bridge.
    } on PlatformException {
      // A malformed platform delivery should not prevent the app from opening.
    }
  }

  void _emit(String? path) {
    if (path != null && path.trim().isNotEmpty && !_files.isClosed) {
      _files.add(path);
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _files.close();
  }
}
