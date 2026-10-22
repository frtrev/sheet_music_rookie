import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/composition.dart';

class ScorePlaybackService {
  ScorePlaybackService({AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      isPlaying.value = false;
      onComplete?.call();
    });
    _positionSubscription = _player.onPositionChanged.listen((value) {
      position.value = value;
    });
  }

  final AudioPlayer _player;
  late final StreamSubscription<void> _completionSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  VoidCallback? onComplete;

  Future<bool> play(
    Composition composition, {
    Duration startAt = Duration.zero,
  }) async {
    final bytes = await compute(_renderPianoWave, composition);
    if (bytes == null) return false;
    await _player.stop();
    position.value = startAt;
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.play(
      BytesSource(bytes, mimeType: 'audio/wav'),
      position: startAt > Duration.zero ? startAt : null,
    );
    isPlaying.value = true;
    return true;
  }

  Future<void> seek(Duration target) async {
    position.value = target;
    if (isPlaying.value) await _player.seek(target);
  }

  Future<void> stop({bool resetPosition = false}) async {
    // Mark playback stopped before the platform call. Some native players emit
    // a final zero-position event from stop(), which must not look like a seek.
    isPlaying.value = false;
    await _player.stop();
    if (resetPosition) position.value = Duration.zero;
  }

  Future<void> dispose() async {
    await _completionSubscription.cancel();
    await _positionSubscription.cancel();
    await _player.dispose();
    isPlaying.dispose();
    position.dispose();
  }
}

Uint8List? _renderPianoWave(Composition composition) =>
    const PianoWaveSynthesizer().render(composition);

int playbackMidiPitch(Composition composition, int writtenMidiPitch) =>
    (writtenMidiPitch + composition.octaveRange.semitones)
        .clamp(0, 127)
        .toInt();

/// Produces a self-contained mono WAV with a percussive, harmonic-rich piano
/// timbre. Generating it in memory keeps playback fully offline and avoids a
/// large sample or SoundFont dependency.
class PianoWaveSynthesizer {
  const PianoWaveSynthesizer({this.sampleRate = 24000});

  final int sampleRate;

  Uint8List? render(Composition composition) {
    final tones = _collectTones(composition);
    final totalTicks = _scoreDurationTicks(composition);
    if (totalTicks == 0) return null;
    final secondsPerTick = 60 / composition.tempoBpm / 480;
    final sampleCount = math.max(
      1,
      (totalTicks * secondsPerTick * sampleRate).ceil(),
    );
    final samples = Float64List(sampleCount);

    for (final tone in tones) {
      final frequency = 440 * math.pow(2, (tone.midiPitch - 69) / 12);
      final startSample = (tone.startTick * secondsPerTick * sampleRate)
          .round();
      final toneSamples = (tone.durationTicks * secondsPerTick * sampleRate)
          .round();
      for (
        var index = 0;
        index < toneSamples && startSample + index < sampleCount;
        index++
      ) {
        final time = index / sampleRate;
        final remaining = (toneSamples - index) / sampleRate;
        final attack = (time / .008).clamp(0.0, 1.0);
        final release = (remaining / .07).clamp(0.0, 1.0);
        final envelope = attack * release * math.exp(-1.8 * time);
        final phase = 2 * math.pi * frequency * time;
        final timbre =
            .72 * math.sin(phase) +
            .20 * math.sin(phase * 2.002) +
            .10 * math.sin(phase * 3.006) +
            .045 * math.sin(phase * 4.012);
        samples[startSample + index] += .42 * envelope * timbre;
      }
    }

    return _encodeWave(samples);
  }

  List<_Tone> _collectTones(Composition composition) {
    final capacity = composition.beatsPerMeasure * 480;
    final tones = <_Tone>[];
    for (final measure in composition.measures) {
      for (final note in measure.notes) {
        final absoluteStart = measure.index * capacity + note.startTick;
        if (note.isRest) continue;
        if (note.tieFromPrevious &&
            tones.isNotEmpty &&
            tones.last.midiPitch ==
                playbackMidiPitch(composition, note.midiPitch) &&
            tones.last.startTick + tones.last.durationTicks == absoluteStart) {
          tones.last.durationTicks += note.durationTicks;
        } else {
          tones.add(
            _Tone(
              playbackMidiPitch(composition, note.midiPitch),
              absoluteStart,
              note.durationTicks,
            ),
          );
        }
      }
    }
    tones.sort((a, b) => a.startTick.compareTo(b.startTick));
    return tones;
  }

  int _scoreDurationTicks(Composition composition) {
    final capacity = composition.beatsPerMeasure * 480;
    var result = 0;
    for (final measure in composition.measures) {
      for (final note in measure.notes) {
        result = math.max(
          result,
          measure.index * capacity + note.startTick + note.durationTicks,
        );
      }
    }
    return result;
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
      final value = (samples[index].clamp(-1.0, 1.0) * 32767).round();
      bytes.setInt16(44 + index * 2, value, Endian.little);
    }
    return result;
  }
}

class _Tone {
  _Tone(this.midiPitch, this.startTick, this.durationTicks);
  final int midiPitch;
  final int startTick;
  int durationTicks;
}
