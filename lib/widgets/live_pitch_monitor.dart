import '../l10n/l10n.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../audio/microphone_service.dart';
import '../models/pitch_detection_result.dart';

class LivePitchMonitor extends StatelessWidget {
  const LivePitchMonitor({
    super.key,
    required this.status,
    required this.pitch,
    required this.durationMs,
  });

  final ValueListenable<MicrophoneStatus> status;
  final ValueListenable<PitchDetectionResult?> pitch;
  final ValueListenable<int> durationMs;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ValueListenableBuilder<MicrophoneStatus>(
          valueListenable: status,
          builder: (context, micStatus, _) =>
              ValueListenableBuilder<PitchDetectionResult?>(
                valueListenable: pitch,
                builder: (context, result, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StatusDot(status: micStatus),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.microphoneStatus(
                              _statusLabel(context, micStatus),
                            ),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            context.l10n.detectedNote,
                            result == null
                                ? '—'
                                : '${context.l10n.noteName(result.noteName)}${result.octave}',
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            context.l10n.frequency,
                            result == null
                                ? '—'
                                : '${result.frequencyHz.toStringAsFixed(1)} Hz',
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            context.l10n.confidence,
                            result == null
                                ? '—'
                                : '${(result.confidence * 100).round()}%',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            context.l10n.pitchOffset,
                            result == null
                                ? '—'
                                : '${result.centsDeviation >= 0 ? '+' : ''}${result.centsDeviation.toStringAsFixed(1)} cents',
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            context.l10n.amplitude,
                            result == null
                                ? '—'
                                : '${result.dbfs.toStringAsFixed(1)} dBFS',
                          ),
                        ),
                        Expanded(
                          child: ValueListenableBuilder<int>(
                            valueListenable: durationMs,
                            builder: (context, value, child) => _Metric(
                              context.l10n.currentDuration,
                              '$value ms',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TuningBar(cents: result?.centsDeviation),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, MicrophoneStatus value) =>
      switch (value) {
        MicrophoneStatus.starting => context.l10n.starting,
        MicrophoneStatus.listening => context.l10n.listening,
        MicrophoneStatus.voiceDetected => context.l10n.voiceDetected,
        MicrophoneStatus.silence => context.l10n.silence,
        MicrophoneStatus.paused => context.l10n.paused,
        MicrophoneStatus.unavailable => context.l10n.unavailable,
      };
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final MicrophoneStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MicrophoneStatus.voiceDetected => Theme.of(context).colorScheme.primary,
      MicrophoneStatus.listening ||
      MicrophoneStatus.silence => Theme.of(context).colorScheme.secondary,
      MicrophoneStatus.unavailable => Colors.red,
      _ => Colors.grey,
    };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TuningBar extends StatelessWidget {
  const _TuningBar({required this.cents});
  final double? cents;
  @override
  Widget build(BuildContext context) {
    final normalized = ((cents ?? 0).clamp(-50, 50) + 50) / 100;
    final label = cents == null
        ? context.l10n.noPitch
        : (cents! < -8
              ? context.l10n.flat
              : (cents! > 8 ? context.l10n.sharp : context.l10n.inTune));
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(context.l10n.flatIndicator)),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(
                context.l10n.sharpIndicator,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) => Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(
                    colors: [Colors.blueGrey, Colors.green, Colors.deepOrange],
                  ),
                ),
              ),
              Positioned(
                left: (constraints.maxWidth - 4) * normalized,
                child: Container(
                  width: 4,
                  height: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
