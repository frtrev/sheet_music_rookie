import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class MetronomeService {
  MetronomeService({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  int? _tempoBpm;

  Future<void> start(int tempoBpm) async {
    if (isRunning.value && _tempoBpm == tempoBpm) return;
    await _player.stop();
    await _player.setAudioContext(
      AudioContextConfig(
        route: AudioContextConfigRoute.speaker,
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build(),
    );
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(
      BytesSource(
        const MetronomeWaveSynthesizer().render(tempoBpm),
        mimeType: 'audio/wav',
      ),
      volume: .55,
    );
    _tempoBpm = tempoBpm;
    isRunning.value = true;
  }

  Future<void> stop() async {
    await _player.stop();
    _tempoBpm = null;
    isRunning.value = false;
  }

  Future<void> dispose() async {
    await _player.dispose();
    isRunning.dispose();
  }
}

/// Generates one four-beat bar which can be looped without timer drift.
/// The first beat is higher so the start of each 4/4 measure is audible.
class MetronomeWaveSynthesizer {
  const MetronomeWaveSynthesizer({this.sampleRate = 16000});

  final int sampleRate;

  Uint8List render(int tempoBpm) {
    final safeTempo = tempoBpm.clamp(30, 300);
    final samplesPerBeat = (sampleRate * 60 / safeTempo).round();
    final samples = Float64List(samplesPerBeat * 4);
    final clickSamples = (sampleRate * .035).round();

    for (var beat = 0; beat < 4; beat++) {
      final frequency = beat == 0 ? 1500.0 : 1000.0;
      final amplitude = beat == 0 ? .9 : .68;
      final start = beat * samplesPerBeat;
      for (var index = 0; index < clickSamples; index++) {
        final time = index / sampleRate;
        final envelope = math.exp(-85 * time);
        final tone = math.sin(2 * math.pi * frequency * time);
        final noise = math.sin(2 * math.pi * frequency * 2.37 * time);
        samples[start + index] = amplitude * envelope * (tone + .18 * noise);
      }
    }

    return _encodeWave(samples);
  }

  Uint8List _encodeWave(Float64List samples) {
    final result = Uint8List(44 + samples.length * 2);
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
    bytes.setUint32(40, samples.length * 2, Endian.little);
    for (var index = 0; index < samples.length; index++) {
      bytes.setInt16(
        44 + index * 2,
        (samples[index].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }
    return result;
  }
}
