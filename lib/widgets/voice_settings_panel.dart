import '../l10n/l10n.dart';

import 'package:flutter/material.dart';

import '../models/voice_detection_settings.dart';

class VoiceSettingsPanel extends StatelessWidget {
  const VoiceSettingsPanel({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final VoiceDetectionSettings value;
  final ValueChanged<VoiceDetectionSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingSlider(
          label: context.l10n.practiceDifficulty,
          value: value.practiceDifficulty.index.toDouble(),
          min: 0,
          max: 2,
          divisions: 2,
          formatter: (v) =>
              context.l10n.label(PracticeDifficulty.values[v.round()].label),
          onChanged: (v) => onChanged(
            value.copyWith(
              practiceDifficulty: PracticeDifficulty.values[v.round()],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.label(value.practiceDifficulty.description),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        _SettingSlider(
          label: context.l10n.pitchStability,
          value: value.pitchStabilityMs.toDouble(),
          min: 25,
          max: 400,
          divisions: 15,
          suffix: 'ms',
          onChanged: (v) =>
              onChanged(value.copyWith(pitchStabilityMs: v.round())),
        ),
        _SettingSlider(
          label: context.l10n.pitchToleranceCapturePractice,
          value: value.pitchToleranceCents,
          min: 10,
          max: 100,
          divisions: 18,
          formatter: (v) => context.l10n.toleranceCents(v.round()),
          onChanged: (v) => onChanged(value.copyWith(pitchToleranceCents: v)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(context.l10n.recordingAnalysis),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<RecordingAnalysisMode>(
          initialValue: value.recordingAnalysisMode,
          isExpanded: true,
          items: [
            DropdownMenuItem(
              value: RecordingAnalysisMode.live,
              child: Text(context.l10n.live),
            ),
            DropdownMenuItem(
              value: RecordingAnalysisMode.phrase,
              child: Text(context.l10n.reviewAfterAPhrase),
            ),
          ],
          onChanged: (mode) {
            if (mode != null) {
              onChanged(value.copyWith(recordingAnalysisMode: mode));
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          context
              .l10n
              .phraseModeWaitsForSilenceThenShowsAPitchTraceAndPreviewNotesOnlyAcceptedPhrasesAreWrittenToTheScorePlayOrSingOneNoteAtATime,
        ),
        if (value.recordingAnalysisMode == RecordingAnalysisMode.phrase)
          _SettingSlider(
            label: context.l10n.phraseSilence,
            value: value.phraseSilenceMs.toDouble(),
            min: 400,
            max: 2500,
            divisions: 21,
            suffix: 'ms',
            onChanged: (v) =>
                onChanged(value.copyWith(phraseSilenceMs: v.round())),
          ),
        const SizedBox(height: 16),
        _SettingSlider(
          label: context.l10n.automaticCursorPosition,
          value: value.cursorFollowFraction,
          min: .25,
          max: .60,
          divisions: 7,
          formatter: (v) => context.l10n.cursorFromLeft((v * 100).round()),
          onChanged: (v) => onChanged(value.copyWith(cursorFollowFraction: v)),
        ),
        _SettingSlider(
          label: context.l10n.voicePolishTestPlayback,
          value: value.voicePolish,
          min: 0,
          max: 1,
          divisions: 20,
          formatter: (v) => v == 0 ? context.l10n.off : '${(v * 100).round()}%',
          onChanged: (v) => onChanged(value.copyWith(voicePolish: v)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              context
                  .l10n
                  .aClearerSmootherVoiceWithSubtleRoomAmbienceAppliesToYourNextTestPlaybackPitchAndScoringStayUnchanged,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        _SettingSlider(
          label: context.l10n.minimumFrequency,
          value: value.minimumFrequency,
          min: 50,
          max: 300,
          divisions: 50,
          suffix: 'Hz',
          onChanged: (v) => onChanged(value.copyWith(minimumFrequency: v)),
        ),
        _SettingSlider(
          label: context.l10n.maximumFrequency,
          value: value.maximumFrequency,
          min: 600,
          max: 2000,
          divisions: 56,
          suffix: 'Hz',
          onChanged: (v) => onChanged(value.copyWith(maximumFrequency: v)),
        ),
        _SettingSlider(
          label: context.l10n.minimumConfidence,
          value: value.minimumConfidence,
          min: .4,
          max: .98,
          divisions: 58,
          formatter: (v) => '${(v * 100).round()}%',
          onChanged: (v) => onChanged(value.copyWith(minimumConfidence: v)),
        ),
        _SettingSlider(
          label: context.l10n.minimumNoteDuration,
          value: value.minimumNoteDurationMs.toDouble(),
          min: 50,
          max: 500,
          divisions: 45,
          suffix: 'ms',
          onChanged: (v) =>
              onChanged(value.copyWith(minimumNoteDurationMs: v.round())),
        ),
        _SettingSlider(
          label: context.l10n.silenceThreshold,
          value: value.silenceThresholdDb,
          min: -70,
          max: -20,
          divisions: 50,
          suffix: 'dBFS',
          onChanged: (v) => onChanged(value.copyWith(silenceThresholdDb: v)),
        ),
        _SettingSlider(
          label: context.l10n.silenceDuration,
          value: value.silenceDurationMs.toDouble(),
          min: 50,
          max: 800,
          divisions: 30,
          suffix: 'ms',
          onChanged: (v) =>
              onChanged(value.copyWith(silenceDurationMs: v.round())),
        ),
        _SettingSlider(
          label: context.l10n.repeatedSyllableGap,
          value: value.articulationGapMs.toDouble(),
          min: 15,
          max: 150,
          divisions: 27,
          suffix: 'ms',
          onChanged: (v) =>
              onChanged(value.copyWith(articulationGapMs: v.round())),
        ),
        _SettingSlider(
          label: context.l10n.smoothingWindow,
          value: value.smoothingWindow.toDouble(),
          min: 1,
          max: 12,
          divisions: 11,
          suffix: context.l10n.frames,
          onChanged: (v) =>
              onChanged(value.copyWith(smoothingWindow: v.round())),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => onChanged(const VoiceDetectionSettings()),
            icon: const Icon(Icons.restart_alt),
            label: Text(context.l10n.resetToDefaults),
          ),
        ),
      ],
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.suffix,
    this.formatter,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String? suffix;
  final String Function(double)? formatter;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final display =
        formatter?.call(value) ?? '${value.round()} ${suffix ?? ''}';
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(label),
            Text(
              display,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
