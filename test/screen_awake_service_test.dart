import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/services/screen_awake_service.dart';

void main() {
  test('screen stays awake while any transport mode is active', () async {
    final changes = <bool>[];
    final service = ScreenAwakeService(
      setter: (enabled) async => changes.add(enabled),
    );

    service.update(recording: true, playing: false, practicing: false);
    service.update(recording: true, playing: true, practicing: false);
    service.update(recording: false, playing: false, practicing: true);
    service.update(recording: false, playing: false, practicing: false);
    await service.dispose();

    expect(changes, [true, false]);
    expect(service.requested, isFalse);
  });
}
