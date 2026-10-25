import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sheet_music_rookie/models/voice_detection_settings.dart';
import 'package:sheet_music_rookie/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('practice difficulty persists with voice settings', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService();

    await service.save(
      const VoiceDetectionSettings(
        practiceDifficulty: PracticeDifficulty.advanced,
        cursorFollowFraction: .35,
      ),
    );

    final loaded = await service.load();
    expect(loaded.practiceDifficulty, PracticeDifficulty.advanced);
    expect(loaded.cursorFollowFraction, .35);
  });
}
