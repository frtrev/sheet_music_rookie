import 'package:shared_preferences/shared_preferences.dart';

import '../models/voice_detection_settings.dart';

class SettingsService {
  static const _prefix = 'voice.';

  Future<VoiceDetectionSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const defaults = VoiceDetectionSettings();
    return VoiceDetectionSettings(
      recordingAnalysisMode: RecordingAnalysisMode.values.firstWhere(
        (mode) =>
            mode.name == prefs.getString('${_prefix}recordingAnalysisMode'),
        orElse: () => defaults.recordingAnalysisMode,
      ),
      phraseSilenceMs:
          (prefs.getInt('${_prefix}phraseSilenceMs') ??
                  defaults.phraseSilenceMs)
              .clamp(400, 2500),
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
      practiceDifficulty: PracticeDifficulty.values.firstWhere(
        (value) =>
            value.name == prefs.getString('${_prefix}practiceDifficulty'),
        orElse: () => defaults.practiceDifficulty,
      ),
      cursorFollowFraction:
          prefs.getDouble('${_prefix}cursorFollowFraction') ??
          defaults.cursorFollowFraction,
      voicePolish:
          (prefs.getDouble('${_prefix}voicePolish') ?? defaults.voicePolish)
              .clamp(0.0, 1.0),
      smoothingWindow:
          prefs.getInt('${_prefix}smoothing') ?? defaults.smoothingWindow,
    );
  }

  Future<void> save(VoiceDetectionSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(
        '${_prefix}recordingAnalysisMode',
        value.recordingAnalysisMode.name,
      ),
      prefs.setInt('${_prefix}phraseSilenceMs', value.phraseSilenceMs),
      prefs.setDouble('${_prefix}minFrequency', value.minimumFrequency),
      prefs.setDouble('${_prefix}maxFrequency', value.maximumFrequency),
      prefs.setDouble('${_prefix}confidence', value.minimumConfidence),
      prefs.setInt('${_prefix}minDuration', value.minimumNoteDurationMs),
      prefs.setInt('${_prefix}stability', value.pitchStabilityMs),
      prefs.setDouble('${_prefix}silenceThreshold', value.silenceThresholdDb),
      prefs.setInt('${_prefix}silenceDuration', value.silenceDurationMs),
      prefs.setInt('${_prefix}articulationGap', value.articulationGapMs),
      prefs.setDouble('${_prefix}tolerance', value.pitchToleranceCents),
      prefs.setString(
        '${_prefix}practiceDifficulty',
        value.practiceDifficulty.name,
      ),
      prefs.setDouble(
        '${_prefix}cursorFollowFraction',
        value.cursorFollowFraction,
      ),
      prefs.setInt('${_prefix}smoothing', value.smoothingWindow),
      prefs.setDouble(
        '${_prefix}voicePolish',
        value.voicePolish.clamp(0.0, 1.0),
      ),
    ]);
  }
}
