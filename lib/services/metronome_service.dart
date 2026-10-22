import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/composition.dart';

class MetronomeService {
  MetronomeService({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  int? _tempoBpm;
  MetronomeMode? _mode;
  double? _volume;

  Future<void> start(
    int tempoBpm,
    MetronomeMode mode, {
    double volume = .55,
  }) async {
    if (mode == MetronomeMode.off) {
      await stop();
      return;
    }
    final safeVolume = volume.clamp(0.0, 1.0).toDouble();
    if (isRunning.value && _tempoBpm == tempoBpm && _mode == mode) {
      if (_volume != safeVolume) {
        await _player.setVolume(safeVolume);
        _volume = safeVolume;
      }
      return;
    }
    await _player.stop();
    await _player.setAudioContext(
      AudioContextConfig(
        route: AudioContextConfigRoute.speaker,
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build(),
    );
    // A short looping WAV can incur a decoder gap at every bar boundary on
    // mobile platforms. Use one continuous ten-minute track instead; loop is
    // retained only as a fallback for exceptionally long recording sessions.
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(
      BytesSource(
        const MetronomeWaveSynthesizer().render(
          tempoBpm,
          mode,
          measureCount: _continuousTrackMeasures(tempoBpm),
        ),
        mimeType: 'audio/wav',
      ),
      volume: safeVolume,
    );
    _tempoBpm = tempoBpm;
    _mode = mode;
    _volume = safeVolume;
    isRunning.value = true;
  }

  static int _continuousTrackMeasures(int tempoBpm) {
    const targetSeconds = 600;
    const beatsPerMeasure = 4;
    final secondsPerMeasure = beatsPerMeasure * 60 / tempoBpm.clamp(30, 300);
    return (targetSeconds / secondsPerMeasure).ceil();
  }

  Future<void> stop() async {
    await _player.stop();
    _tempoBpm = null;
    _mode = null;
    _volume = null;
    isRunning.value = false;
  }

  Future<void> dispose() async {
    await _player.dispose();
    isRunning.dispose();
  }
}

/// Generates a continuous click track without decoder boundaries between bars.
/// In accented mode the first beat is higher so each measure remains audible.
class MetronomeWaveSynthesizer {
  const MetronomeWaveSynthesizer({this.sampleRate = 12000});

  final int sampleRate;

  Uint8List render(
    int tempoBpm,
    MetronomeMode mode, {
    int beatsPerMeasure = 4,
    int measureCount = 1,
  }) {
    final safeTempo = tempoBpm.clamp(30, 300);
    final samplesPerBeat = (sampleRate * 60 / safeTempo).round();
    final sampleCount =
        samplesPerBeat * beatsPerMeasure * measureCount.clamp(1, 10000);
    final result = Uint8List(44 + sampleCount * 2);
    final bytes = ByteData.sublistView(result);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        bytes.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, result.length - 8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, sampleCount * 2, Endian.little);

    if (mode == MetronomeMode.off) return result;
    final clickSamples = (sampleRate * .028).round();
    final beatCount = beatsPerMeasure * measureCount;
    for (var beat = 0; beat < beatCount; beat++) {
      final accented =
          mode == MetronomeMode.accented && beat % beatsPerMeasure == 0;
      final frequency = accented ? 1650.0 : 1050.0;
      final amplitude = switch (mode) {
        MetronomeMode.accented => accented ? .78 : .46,
        MetronomeMode.single => .24,
        MetronomeMode.off => 0.0,
      };
      final start = beat * samplesPerBeat;
      for (var index = 0; index < clickSamples; index++) {
        final time = index / sampleRate;
        final envelope = math.exp(-115 * time);
        final tsk =
            math.sin(2 * math.pi * frequency * time) +
            .32 * math.sin(2 * math.pi * frequency * 2.71 * time) +
            .14 * math.sin(2 * math.pi * frequency * 4.13 * time);
        final value = (amplitude * envelope * tsk).clamp(-1.0, 1.0);
        bytes.setInt16(
          44 + (start + index) * 2,
          (value * 32767).round(),
          Endian.little,
        );
      }
    }
    return result;
  }
}

/// Adds clicks directly to an existing audio buffer. Mixing them into score
/// playback keeps every click on the exact same sample grid as the notes.
void mixMetronomeClicks(
  Float64List samples, {
  required int sampleRate,
  required int tempoBpm,
  required int beatsPerMeasure,
  required MetronomeMode mode,
  double gain = 1,
}) {
  if (mode == MetronomeMode.off || samples.isEmpty) return;
  final samplesPerBeat = (sampleRate * 60 / tempoBpm.clamp(30, 300)).round();
  final clickSamples = (sampleRate * .028).round();
  final beatCount = (samples.length / samplesPerBeat).ceil();

  for (var beat = 0; beat < beatCount; beat++) {
    final accented =
        mode == MetronomeMode.accented && beat % beatsPerMeasure == 0;
    final frequency = accented ? 1650.0 : 1050.0;
    final amplitude = switch (mode) {
      MetronomeMode.accented => accented ? .78 : .46,
      MetronomeMode.single => .24,
      MetronomeMode.off => 0.0,
    };
    final start = beat * samplesPerBeat;
    for (
      var index = 0;
      index < clickSamples && start + index < samples.length;
      index++
    ) {
      final time = index / sampleRate;
      final envelope = math.exp(-115 * time);
      final tsk =
          math.sin(2 * math.pi * frequency * time) +
          .32 * math.sin(2 * math.pi * frequency * 2.71 * time) +
          .14 * math.sin(2 * math.pi * frequency * 4.13 * time);
      samples[start + index] += gain * amplitude * envelope * tsk;
    }
  }
}
