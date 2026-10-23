import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../audio/microphone_service.dart';
import '../models/pitch_detection_result.dart';

class PitchGaugeReading {
  const PitchGaugeReading({required this.errorCents});

  final double errorCents;

  /// Keeps the moving marker inside the gauge while still showing errors up
  /// to two semitones in either direction.
  double get position => (errorCents / 200).clamp(-1.0, 1.0).toDouble();

  /// Green at the target, yellow at 50 cents, and red at a semitone or more.
  Color get color {
    final distance = errorCents.abs().clamp(0.0, 100.0).toDouble();
    return HSVColor.fromAHSV(1, 120 * (1 - distance / 100), .78, .78).toColor();
  }

  String get description {
    final rounded = errorCents.round();
    if (rounded.abs() <= 2) return 'on pitch';
    return '${rounded.abs()} cents ${rounded > 0 ? 'sharp' : 'flat'}';
  }

  static PitchGaugeReading? from({
    required PitchDetectionResult? detectedPitch,
    required int? targetMidiPitch,
  }) {
    if (detectedPitch == null ||
        targetMidiPitch == null ||
        detectedPitch.frequencyHz <= 0) {
      return null;
    }
    final targetHz = 440 * math.pow(2, (targetMidiPitch - 69) / 12);
    final errorCents =
        1200 * math.log(detectedPitch.frequencyHz / targetHz) / math.ln2;
    return PitchGaugeReading(errorCents: errorCents);
  }
}

class PracticePitchGauge extends StatelessWidget {
  const PracticePitchGauge({
    super.key,
    required this.active,
    required this.targetMidiPitch,
    required this.pitch,
    required this.microphoneStatus,
  });

  final bool active;
  final int? targetMidiPitch;
  final ValueListenable<PitchDetectionResult?> pitch;
  final ValueListenable<MicrophoneStatus> microphoneStatus;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MicrophoneStatus>(
      valueListenable: microphoneStatus,
      builder: (context, status, _) =>
          ValueListenableBuilder<PitchDetectionResult?>(
            valueListenable: pitch,
            builder: (context, detectedPitch, _) {
              final reading = active && status == MicrophoneStatus.voiceDetected
                  ? PitchGaugeReading.from(
                      detectedPitch: detectedPitch,
                      targetMidiPitch: targetMidiPitch,
                    )
                  : null;
              return _PitchGauge(reading: reading, active: active);
            },
          ),
    );
  }
}

class _PitchGauge extends StatelessWidget {
  const _PitchGauge({required this.reading, required this.active});

  static const _width = 34.0;
  static const _markerWidth = 18.0;
  static const _markerHeight = 4.0;
  static const _verticalInset = 14.0;

  final PitchGaugeReading? reading;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = reading?.color ?? scheme.outlineVariant;
    final semantics = !active
        ? 'Pitch gauge inactive'
        : reading == null
        ? 'Pitch gauge waiting for a tone'
        : 'Pitch ${reading!.description}';

    return Semantics(
      label: semantics,
      liveRegion: active,
      child: SizedBox(
        width: _width,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final travel = math.max(
              0.0,
              constraints.maxHeight - _verticalInset * 2 - _markerHeight,
            );
            final normalized = reading?.position ?? 0;
            final markerTop = _verticalInset + (1 - normalized) * travel / 2;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: reading == null ? .08 : .16),
                border: Border(right: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: _verticalInset,
                    bottom: _verticalInset,
                    width: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Positioned(
                    top: constraints.maxHeight / 2 - .5,
                    width: _markerWidth + 6,
                    height: 1,
                    child: ColoredBox(
                      color: scheme.onSurface.withValues(alpha: .24),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOut,
                    top: markerTop,
                    width: _markerWidth,
                    height: _markerHeight,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: reading == null
                            ? null
                            : [
                                BoxShadow(
                                  color: color.withValues(alpha: .35),
                                  blurRadius: 5,
                                ),
                              ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
