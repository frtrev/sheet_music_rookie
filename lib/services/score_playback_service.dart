import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart' as sf;

import '../audio/general_user_soundfont.dart';

import '../models/composition.dart';
import '../audio/instrument_voice.dart';
import '../music/performance_plan.dart';
import '../models/musical_note.dart';
import 'metronome_service.dart';

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

  PerformancePlan? _plan;
  final AudioPlayer _player;

  int scoreTickAt(Duration elapsed, int tempoBpm) {
    final tick = (elapsed.inMicroseconds * tempoBpm * 480 / 60000000).round();
    return _plan?.sourceTickAt(tick) ?? tick;
  }

  Future<void> seekScore(Duration target, int tempoBpm) async {
    final tick = (target.inMicroseconds * tempoBpm * 480 / 60000000).round();
    final current = (position.value.inMicroseconds * tempoBpm * 480 / 60000000)
        .round();
    final performed = _plan?.performanceTickAt(tick, nearTick: current) ?? tick;
    await seek(
      Duration(microseconds: (performed * 60000000 / (tempoBpm * 480)).round()),
    );
  }

  late final StreamSubscription<void> _completionSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  VoidCallback? onComplete;

  Future<bool> play(
    Composition composition, {
    Duration startAt = Duration.zero,
  }) async {
    final plan = PerformancePlan(composition);
    final performedTick = plan.performanceTickAt(
      (startAt.inMicroseconds * composition.tempoBpm * 480 / 60000000).round(),
    );
    startAt = Duration(
      microseconds: (performedTick * 60000000 / (composition.tempoBpm * 480))
          .round(),
    );
    final bank = await GeneralUserSoundFont.load();
    final bytes = await compute(_renderPianoWave, (
      composition: plan.expanded,
      soundFont: bank,
    ));
    _plan = plan;
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

  Future<bool> playWave(Uint8List bytes) async {
    if (bytes.isEmpty) return false;
    _plan = null;
    await _player.stop();
    position.value = Duration.zero;
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
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

Uint8List? _renderPianoWave(
  ({Composition composition, Uint8List soundFont}) request,
) =>
    PianoWaveSynthesizer(soundFont: ByteData.sublistView(request.soundFont))
        .render(request.composition);

int playbackMidiPitch(
  Composition composition,
  int writtenMidiPitch, {
  NoteAccidental accidental = NoteAccidental.automatic,
}) {
  final pitchClass = writtenMidiPitch % 12;
  final isNatural = const {0, 2, 4, 5, 7, 9, 11}.contains(pitchClass);
  final keyAlteration = isNatural && accidental != NoteAccidental.natural
      ? composition.keySignature.alterationForNaturalPitchClass(pitchClass)
      : 0;
  return (writtenMidiPitch + keyAlteration + composition.octaveRange.semitones)
      .clamp(0, 127)
      .toInt();
}

/// Renders the selected SoundFont instrument to an offline mono WAV.
/// Calls without a supplied bank retain the legacy modeled voices.
class PianoWaveSynthesizer {
  const PianoWaveSynthesizer({this.sampleRate = 24000, this.soundFont});

  final int sampleRate;
  final ByteData? soundFont;

  Uint8List? render(Composition source) {
    final composition = PerformancePlan(source).expanded;
    final tones = _collectTones(composition);
    final totalTicks = _scoreDurationTicks(composition);
    if (totalTicks == 0) return null;
    final secondsPerTick = 60 / composition.tempoBpm / 480;
    final sampleCount = math.max(
      1,
      (totalTicks * secondsPerTick * sampleRate).ceil(),
    );
    final samples = Float64List(
      sampleCount + (soundFont == null ? 0 : (sampleRate * .35).round()),
    );

    if (soundFont != null) {
      _renderSoundFont(samples, tones, composition, secondsPerTick);
    } else {
      for (final tone in tones) {
        final frequency = 440 * math.pow(2, (tone.midiPitch - 69) / 12);
        final startSample = (tone.startTick * secondsPerTick * sampleRate)
            .round();
        final toneSamples = (tone.durationTicks * secondsPerTick * sampleRate)
            .round();
        final voice = InstrumentVoice(
          composition.playbackInstrument,
          frequency.toDouble(),
          sampleRate,
        );
        for (
          var index = 0;
          index < toneSamples && startSample + index < sampleCount;
          index++
        ) {
          final time = index / sampleRate;
          final remaining = (toneSamples - index) / sampleRate;
          samples[startSample + index] +=
              composition.playbackVolume * voice.sample(time, remaining);
        }
      }
    }

    mixMetronomeClicks(
      Float64List.sublistView(samples, 0, sampleCount),
      sampleRate: sampleRate,
      tempoBpm: composition.tempoBpm,
      beatsPerMeasure: composition.beatsPerMeasure,
      accentedBeatIndices: {
        for (var index = 0; index < composition.measures.length; index++)
          if (composition.measureStartTick(index) % 480 == 0)
            composition.measureStartTick(index) ~/ 480,
      },
      mode: composition.metronomeMode,
      gain: composition.metronomeVolume,
    );

    return _encodeWave(samples);
  }

  void _renderSoundFont(
    Float64List samples,
    List<_Tone> tones,
    Composition composition,
    double secondsPerTick,
  ) {
    final synth = sf.Synthesizer.loadByteData(
      soundFont!,
      sf.SynthesizerSettings(
        sampleRate: sampleRate,
        maximumPolyphony: 32,
        enableReverbAndChorus: true,
      ),
    );
    final preset = synth.soundFont.presets.indexWhere(
      (p) =>
          p.bankNumber == 0 &&
          p.patchNumber == composition.playbackInstrument.midiProgram - 1,
    );
    if (preset < 0) {
      throw StateError(
        'The selected instrument is missing from GeneralUser GS.',
      );
    }
    synth.selectPreset(channel: 0, preset: preset);
    final events = <({int sample, int pitch, bool on})>[];
    for (final tone in tones) {
      events.add((
        sample: (tone.startTick * secondsPerTick * sampleRate).round(),
        pitch: tone.midiPitch,
        on: true,
      ));
      events.add((
        sample:
            ((tone.startTick + tone.durationTicks) *
                    secondsPerTick *
                    sampleRate)
                .round(),
        pitch: tone.midiPitch,
        on: false,
      ));
    }
    events.sort((a, b) {
      final time = a.sample.compareTo(b.sample);
      return time != 0 ? time : (a.on ? 1 : 0).compareTo(b.on ? 1 : 0);
    });
    final left = Float32List(1024);
    final right = Float32List(1024);
    var position = 0;
    void renderUntil(int end) {
      while (position < end) {
        final count = math.min(left.length, end - position);
        final l = Float32List.sublistView(left, 0, count);
        final r = Float32List.sublistView(right, 0, count);
        synth.render(l, r);
        for (var i = 0; i < count; i++) {
          samples[position + i] =
              (l[i] + r[i]) * .5 * composition.playbackVolume;
        }
        position += count;
      }
    }

    for (final event in events) {
      renderUntil(event.sample.clamp(0, samples.length));
      if (event.on) {
        synth.noteOn(channel: 0, key: event.pitch, velocity: 90);
      } else {
        synth.noteOff(channel: 0, key: event.pitch);
      }
    }
    renderUntil(samples.length);
    final fadeSamples = (sampleRate * .01).round();
    for (var i = 0; i < fadeSamples; i++) {
      samples[samples.length - 1 - i] *= i / fadeSamples;
    }
  }

  List<_Tone> _collectTones(Composition composition) {
    final tones = <_Tone>[];
    for (final measure in composition.measures) {
      for (final note in measure.notes) {
        final absoluteStart =
            composition.measureStartTick(measure.index) + note.startTick;
        if (note.isRest) continue;
        if (note.tieFromPrevious &&
            tones.isNotEmpty &&
            tones.last.midiPitch ==
                playbackMidiPitch(
                  composition,
                  note.midiPitch,
                  accidental: note.accidental,
                ) &&
            tones.last.startTick + tones.last.durationTicks == absoluteStart) {
          tones.last.durationTicks += note.durationTicks;
        } else {
          tones.add(
            _Tone(
              playbackMidiPitch(
                composition,
                note.midiPitch,
                accidental: note.accidental,
              ),
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
    var result = 0;
    for (final measure in composition.measures) {
      for (final note in measure.notes) {
        result = math.max(
          result,
          composition.measureStartTick(measure.index) +
              note.startTick +
              note.durationTicks,
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
