import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class GeneralUserSoundFont {
  static const asset = 'assets/soundfonts/GeneralUser-GS.sf2';
  static Future<Uint8List>? _loading;
  static bool _licensesRegistered = false;

  static void registerLicenses() {
    if (_licensesRegistered) return;
    _licensesRegistered = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        ['GeneralUser GS by S. Christian Collins'],
        await rootBundle.loadString(
          'assets/soundfonts/LICENSE-GeneralUser-GS.txt',
        ),
      );
    });
  }

  static Future<Uint8List> load() {
    registerLicenses();
    return _loading ??= _load();
  }

  static Future<Uint8List> _load() async {
    try {
      final data = await rootBundle.load(asset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }
}
