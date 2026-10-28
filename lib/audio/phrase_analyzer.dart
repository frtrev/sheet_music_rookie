import 'dart:math' as math;

import '../models/raw_note_event.dart';
import '../models/pitch_detection_result.dart';
import '../models/musical_note.dart';
import '../models/voice_detection_settings.dart';
import 'microphone_service.dart';
import 'pitch_detector.dart';
import 'note_segmenter.dart';

class PhraseAnalysisRequest {
  const PhraseAnalysisRequest(this.frames, this.settings, this.tempoBpm);
  final List<AudioFrame> frames;
  final VoiceDetectionSettings settings;
  final int tempoBpm;
}

/// Whole-phrase analysis runs in an isolate. Centered pitch filtering can use
/// future frames; onset boundaries are quantized together rather than rounding
/// every note's duration independently.
List<RawNoteEvent> analyzePhrase(PhraseAnalysisRequest request) {
  final frames = request.frames;
  if (frames.isEmpty) return [];
  final settings = request.settings;
  const detector = PitchDetector();
  final pitches = [
    for (final frame in frames)
      detector.analyze(frame.samples, frame.timestampMs, settings),
  ];
  final segmenter = NoteSegmenter();
  final notes = <RawNoteEvent>[];
  final analysisSettings = settings.copyWith(
    pitchStabilityMs: math.min(settings.pitchStabilityMs, 50),
  );
  double previousRms = 0;
  var lastAttack = frames.first.timestampMs;
  for (var i = 0; i < frames.length; i++) {
    var pitch = pitches[i];
    if (pitch != null && pitch.confidence >= settings.minimumConfidence) {
      final neighbors = <double>[
        for (
          var j = math.max(0, i - 1);
          j <= math.min(i + 1, pitches.length - 1);
          j++
        )
          if (pitches[j] != null &&
              pitches[j]!.confidence >= settings.minimumConfidence)
            pitches[j]!.frequencyHz,
      ]..sort();
      final frequency = neighbors[neighbors.length ~/ 2];
      final midi = (69 + 12 * math.log(frequency / 440) / math.ln2).round();
      pitch = PitchDetectionResult(
        timestampMs: pitch.timestampMs,
        frequencyHz: frequency,
        midiNote: midi,
        noteName: pitch.noteName,
        octave: pitch.octave,
        centsDeviation: 0,
        confidence: pitch.confidence,
        rmsAmplitude: pitch.rmsAmplitude,
      );
      // A fresh piano attack can repeat the same pitch without silence.
      if (previousRms > .0001 &&
          pitch.rmsAmplitude > previousRms * 1.8 &&
          pitch.timestampMs - lastAttack > 140 &&
          segmenter.active != null) {
        final ended = segmenter.finish(pitch.timestampMs, analysisSettings);
        if (ended != null) notes.add(ended);
        segmenter.reset();
        lastAttack = pitch.timestampMs;
      }
      previousRms = pitch.rmsAmplitude;
    } else {
      previousRms = 0;
    }
    final update = segmenter.process(
      pitch,
      frames[i].timestampMs,
      analysisSettings,
    );
    if (update.finalized != null) notes.add(update.finalized!);
  }
  // Stop flushes at the last audible frame, excluding the silence delimiter.
  final lastVoiced = pitches.lastWhere(
    (p) =>
        p != null &&
        p.confidence >= settings.minimumConfidence &&
        p.dbfs >= settings.silenceThresholdDb,
    orElse: () => null,
  );
  final last = segmenter.finish(
    lastVoiced?.timestampMs ?? frames.last.timestampMs,
    analysisSettings,
  );
  if (last != null) notes.add(last);
  if (notes.isEmpty) return [];
  final origin = frames.first.timestampMs;
  int grid(int time) =>
      (((time - origin) * request.tempoBpm * 480 / 60000) / 120).round() * 120;
  final output = <RawNoteEvent>[];
  var cursor = 0;
  var timestamp = 0;
  void append(RawNoteEvent source, int ticks, {bool rest = false}) {
    var remaining = ticks;
    while (remaining > 0) {
      final value = NoteValue.values.reversed.firstWhere(
        (v) => v.ticks <= remaining,
      );
      remaining -= value.ticks;
      final end =
          timestamp + (value.ticks * 60000 / (request.tempoBpm * 480)).round();
      output.add(
        RawNoteEvent(
          startTimeMs: timestamp,
          endTimeMs: end,
          frequencyHz: rest ? 0 : source.frequencyHz,
          midiPitch: rest ? 0 : source.midiPitch,
          confidence: source.confidence,
          isRest: rest,
          tieToNext: !rest && remaining > 0,
        ),
      );
      timestamp = end;
    }
  }

  for (var i = 0; i < notes.length; i++) {
    final note = notes[i];
    final start = math.max(cursor, grid(note.startTimeMs));
    if (start > cursor) append(note, start - cursor, rest: true);
    final next = i + 1 < notes.length ? notes[i + 1] : null;
    final endMs =
        next != null &&
            next.startTimeMs - note.endTimeMs < settings.silenceDurationMs
        ? next.startTimeMs
        : note.endTimeMs;
    final end = math.max(start + 120, grid(endMs));
    append(note, end - start);
    cursor = end;
  }
  return output;
}
