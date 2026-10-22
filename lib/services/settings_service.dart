import 'package:shared_preferences/shared_preferences.dart';

import '../models/voice_detection_settings.dart';

class SettingsService {
  static const _prefix = 'voice.';

  Future<VoiceDetectionSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const defaults = VoiceDetectionSettings();
    return VoiceDetectionSettings(
      minimumFrequency:
          prefs.getDouble('${_prefix}minFrequency') ??
          defaults.minimumFrequency,
      maximumFrequency:
          prefs.getDouble('${_prefix}maxFrequency') ??
          defaults.maximumFrequency,
      minimumConfidence:
          prefs.getDouble('${_prefix}confidence') ?? defaults.minimumConfidence,
      minimumNoteDurationMs:
          prefs.getInt('${_prefix}minDuration') ??
          defaults.minimumNoteDurationMs,
      pitchStabilityMs:
          prefs.getInt('${_prefix}stability') ?? defaults.pitchStabilityMs,
      silenceThresholdDb:
          prefs.getDouble('${_prefix}silenceThreshold') ??
          defaults.silenceThresholdDb,
      silenceDurationMs:
          prefs.getInt('${_prefix}silenceDuration') ??
          defaults.silenceDurationMs,
      articulationGapMs:
          prefs.getInt('${_prefix}articulationGap') ??
          defaults.articulationGapMs,
      pitchToleranceCents:
          prefs.getDouble('${_prefix}tolerance') ??
          defaults.pitchToleranceCents,
      smoothingWindow:
          prefs.getInt('${_prefix}smoothing') ?? defaults.smoothingWindow,
    );
  }

  Future<void> save(VoiceDetectionSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setDouble('${_prefix}minFrequency', value.minimumFrequency),
      prefs.setDouble('${_prefix}maxFrequency', value.maximumFrequency),
      prefs.setDouble('${_prefix}confidence', value.minimumConfidence),
      prefs.setInt('${_prefix}minDuration', value.minimumNoteDurationMs),
      prefs.setInt('${_prefix}stability', value.pitchStabilityMs),
      prefs.setDouble('${_prefix}silenceThreshold', value.silenceThresholdDb),
      prefs.setInt('${_prefix}silenceDuration', value.silenceDurationMs),
      prefs.setInt('${_prefix}articulationGap', value.articulationGapMs),
      prefs.setDouble('${_prefix}tolerance', value.pitchToleranceCents),
      prefs.setInt('${_prefix}smoothing', value.smoothingWindow),
    ]);
  }
}
