import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/note_segmenter.dart';
import 'package:sheet_music_rookie/models/pitch_detection_result.dart';
import 'package:sheet_music_rookie/models/voice_detection_settings.dart';

PitchDetectionResult pitch(int time, int midi, double frequency) =>
    PitchDetectionResult(
      timestampMs: time,
      frequencyHz: frequency,
      midiNote: midi,
      noteName: midi == 60 ? 'C' : 'D',
      octave: 4,
      centsDeviation: 0,
      confidence: .96,
      rmsAmplitude: .2,
    );

void main() {
  const settings = VoiceDetectionSettings(
    pitchStabilityMs: 100,
    minimumNoteDurationMs: 150,
    silenceDurationMs: 200,
    smoothingWindow: 1,
  );

  test('a sustained pitch produces one musical event', () {
    final segmenter = NoteSegmenter();
    for (var time = 0; time <= 600; time += 50) {
      segmenter.process(pitch(time, 60, 261.63), time, settings);
    }

    expect(segmenter.active, isNotNull);
    final completed = segmenter.finish(650, settings);
    expect(completed, isNotNull);
    expect(completed!.midiPitch, 60);
    expect(completed.durationMs, 650);
  });

  test('a stable pitch transition finalizes the first event', () {
    final segmenter = NoteSegmenter();
    for (var time = 0; time <= 300; time += 50) {
      segmenter.process(pitch(time, 60, 261.63), time, settings);
    }

    segmenter.process(pitch(350, 62, 293.66), 350, settings);
    segmenter.process(pitch(400, 62, 293.66), 400, settings);
    final transition = segmenter.process(pitch(450, 62, 293.66), 450, settings);
    expect(transition.finalized, isNotNull);
    expect(transition.finalized!.midiPitch, 60);
    expect(transition.finalized!.durationMs, 350);
    expect(transition.active!.midiPitch, 62);
  });

  test('one off-pitch frame does not split a sustained note', () {
    final segmenter = NoteSegmenter();
    for (var time = 0; time <= 300; time += 50) {
      segmenter.process(pitch(time, 60, 261.63), time, settings);
    }

    final glitch = segmenter.process(pitch(350, 62, 293.66), 350, settings);
    final recovered = segmenter.process(pitch(400, 60, 261.63), 400, settings);

    expect(glitch.finalized, isNull);
    expect(recovered.finalized, isNull);
    expect(segmenter.active!.midiPitch, 60);
  });

  test('short unstable sounds are rejected', () {
    final segmenter = NoteSegmenter();
    segmenter.process(pitch(0, 60, 261.63), 0, settings);
    segmenter.process(pitch(50, 60, 261.63), 50, settings);
    expect(segmenter.finish(80, settings), isNull);
  });

  test('an articulated repeat can split the same pitch', () {
    final segmenter = NoteSegmenter();
    for (var time = 0; time <= 300; time += 50) {
      segmenter.process(pitch(time, 60, 261.63), time, settings);
    }
    segmenter.process(null, 350, settings);
    segmenter.process(null, 400, settings);

    final repeat = segmenter.process(pitch(450, 60, 261.63), 450, settings);
    expect(repeat.finalized, isNotNull);
    expect(repeat.finalized!.midiPitch, 60);
    expect(repeat.finalized!.durationMs, 450);
  });

  test('a single very short dropout does not split a sustained syllable', () {
    final segmenter = NoteSegmenter();
    for (var time = 0; time <= 300; time += 50) {
      segmenter.process(pitch(time, 60, 261.63), time, settings);
    }

    segmenter.process(null, 320, settings);
    final resumed = segmenter.process(pitch(340, 60, 261.63), 340, settings);

    expect(resumed.finalized, isNull);
    expect(segmenter.active, isNotNull);
  });
}
