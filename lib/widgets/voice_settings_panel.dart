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
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () => onChanged(
              value.copyWith(
                minimumNoteDurationMs: 100,
                pitchStabilityMs: 70,
                silenceDurationMs: 180,
                articulationGapMs: 35,
                pitchToleranceCents: 45,
                smoothingWindow: 3,
              ),
            ),
            icon: const Icon(Icons.record_voice_over),
            label: const Text('Optimize for “La, La, La”'),
          ),
        ),
        const SizedBox(height: 12),
        _SettingSlider(
          label: 'Minimum frequency',
          value: value.minimumFrequency,
          min: 50,
          max: 300,
          divisions: 50,
          suffix: 'Hz',
          onChanged: (v) => onChanged(value.copyWith(minimumFrequency: v)),
        ),
        _SettingSlider(
          label: 'Maximum frequency',
          value: value.maximumFrequency,
          min: 600,
          max: 2000,
          divisions: 56,
          suffix: 'Hz',
          onChanged: (v) => onChanged(value.copyWith(maximumFrequency: v)),
        ),
        _SettingSlider(
          label: 'Minimum confidence',
          value: value.minimumConfidence,
          min: .4,
          max: .98,
          divisions: 58,
          formatter: (v) => '${(v * 100).round()}%',
          onChanged: (v) => onChanged(value.copyWith(minimumConfidence: v)),
        ),
        _SettingSlider(
          label: 'Minimum note duration',
          value: value.minimumNoteDurationMs.toDouble(),
          min: 50,
          max: 500,
          divisions: 45,
          suffix: 'ms',
          onChanged: (v) =>
              onChanged(value.copyWith(minimumNoteDurationMs: v.round())),
        ),
        _SettingSlider(
          label: 'Pitch stability',
          value: value.pitchStabilityMs.toDouble(),
          min: 25,
          max: 400,
          divisions: 15,
          suffix: 'ms',
          onChanged: (v) =>
              onChanged(value.copyWith(pitchStabilityMs: v.round())),
        ),
        _SettingSlider(
          label: 'Silence threshold',
          value: value.silenceThresholdDb,
          min: -70,
          max: -20,
          divisions: 50,
          suffix: 'dBFS',
          onChanged: (v) => onChanged(value.copyWith(silenceThresholdDb: v)),
        ),
        _SettingSlider(
          label: 'Silence duration',
          value: value.silenceDurationMs.toDouble(),
          min: 50,
          max: 800,
          divisions: 30,
          suffix: 'ms',
          onChanged: (v) =>
              onChanged(value.copyWith(silenceDurationMs: v.round())),
        ),
        _SettingSlider(
          label: 'Repeated-syllable gap',
          value: value.articulationGapMs.toDouble(),
          min: 15,
          max: 150,
          divisions: 27,
          suffix: 'ms',
          onChanged: (v) =>
              onChanged(value.copyWith(articulationGapMs: v.round())),
        ),
        _SettingSlider(
          label: 'Pitch tolerance (capture & practice)',
          value: value.pitchToleranceCents,
          min: 10,
          max: 100,
          divisions: 18,
          formatter: (v) => '±${v.round()} cents',
          onChanged: (v) => onChanged(value.copyWith(pitchToleranceCents: v)),
        ),
        _SettingSlider(
          label: 'Practice difficulty',
          value: value.practiceDifficulty.index.toDouble(),
          min: 0,
          max: 2,
          divisions: 2,
          formatter: (v) => PracticeDifficulty.values[v.round()].label,
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
              value.practiceDifficulty.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        _SettingSlider(
          label: 'Smoothing window',
          value: value.smoothingWindow.toDouble(),
          min: 1,
          max: 12,
          divisions: 11,
          suffix: 'frames',
          onChanged: (v) =>
              onChanged(value.copyWith(smoothingWindow: v.round())),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => onChanged(const VoiceDetectionSettings()),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset to Defaults'),
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
        Row(
          children: [
            Expanded(child: Text(label)),
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
