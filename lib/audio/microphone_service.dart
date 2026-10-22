import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

enum MicrophoneStatus {
  starting,
  listening,
  voiceDetected,
  silence,
  paused,
  unavailable,
}

class AudioFrame {
  const AudioFrame(this.samples, this.timestampMs);
  final Float64List samples;
  final int timestampMs;
}

class MicrophoneService {
  static const sampleRate = 44100;
  static const frameSize = 2048;
  // Overlapping analysis windows improve onset timing from about 46 ms to
  // about 23 ms without sacrificing the pitch resolution of a 2048 sample
  // YIN frame.
  static const hopSize = 1024;

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<AudioFrame> _frames = StreamController.broadcast();
  final List<double> _buffer = [];
  StreamSubscription<Uint8List>? _subscription;
  int _frameStartSample = 0;

  Stream<AudioFrame> get frames => _frames.stream;

  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    await stop();
    _frameStartSample = 0;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    _subscription = stream.listen(_consumeBytes);
    return true;
  }

  void _consumeBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
      _buffer.add(data.getInt16(offset, Endian.little) / 32768.0);
    }
    while (_buffer.length >= frameSize) {
      final timestamp = ((_frameStartSample + frameSize) * 1000 / sampleRate)
          .round();
      _frames.add(
        AudioFrame(
          Float64List.fromList(_buffer.sublist(0, frameSize)),
          timestamp,
        ),
      );
      _buffer.removeRange(0, hopSize);
      _frameStartSample += hopSize;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    _buffer.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _frames.close();
    await _recorder.dispose();
  }
}
