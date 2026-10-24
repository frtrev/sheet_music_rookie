import 'package:wakelock_plus/wakelock_plus.dart';

typedef ScreenWakeSetter = Future<void> Function(bool enabled);

class ScreenAwakeService {
  ScreenAwakeService({ScreenWakeSetter? setter})
    : _setter = setter ?? _setPlatformWakeLock;

  final ScreenWakeSetter _setter;
  Future<void> _pending = Future.value();
  bool _requested = false;

  bool get requested => _requested;

  void update({
    required bool recording,
    required bool playing,
    required bool practicing,
  }) {
    _request(recording || playing || practicing);
  }

  void _request(bool enabled) {
    if (_requested == enabled) return;
    _requested = enabled;
    _pending = _pending.then((_) => _setter(enabled)).onError((_, _) {
      // Screen-awake support should never interrupt a transport action.
    });
  }

  Future<void> dispose() async {
    _request(false);
    await _pending;
  }

  static Future<void> _setPlatformWakeLock(bool enabled) =>
      enabled ? WakelockPlus.enable() : WakelockPlus.disable();
}
