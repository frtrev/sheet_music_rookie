import 'package:flutter/material.dart';

import 'app/app.dart';
import 'audio/general_user_soundfont.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GeneralUserSoundFont.registerLicenses();
  runApp(const SheetMusicRookieApp());
}
