import 'dart:math' as math;

import '../models/pitch_detection_result.dart';
import '../models/raw_note_event.dart';
import '../models/voice_detection_settings.dart';

class NoteSegmentationUpdate {
  const NoteSegmentationUpdate({this.active, this.finalized});
  final RawNoteEvent? active;
  final RawNoteEvent? finalized;
}

class NoteSegmenter {
  int? _candidateMidi;
  int? _candidateStart;
  double _candidateFrequency = 0;
  double _candidateConfidence = 0;
  int _candidateFrames = 0;
  int? _silenceStart;
  RawNoteEvent? _active;

  RawNoteEvent? get active => _active;

  NoteSegmentationUpdate process(
    PitchDetectionResult? result,
    int timestampMs,
    VoiceDetectionSettings settings,
  ) {
    final valid =
        result != null &&
        result.confidence >= settings.minimumConfidence &&
        result.dbfs >= settings.silenceThresholdDb;
    if (!valid) {
      _clearCandidate();
      if (_active == null) return const NoteSegmentationUpdate();
      _silenceStart ??= timestampMs;
      if (timestampMs - _silenceStart! >= settings.silenceDurationMs) {
        return NoteSegmentationUpdate(
          finalized: _finalize(_silenceStart!, settings),
        );
      }
      return NoteSegmentationUpdate(active: _active);
    }

    // A short unvoiced consonant followed by a new attack is useful evidence
    // for repeated notes at the same pitch (for example "La, La, La"). The
    // first note lasts until the next onset so its notated rhythm reflects the
    // onset-to-onset beat rather than only the shorter voiced vowel.
    if (_active != null &&
        _silenceStart != null &&
        timestampMs - _silenceStart! >= settings.articulationGapMs) {
      final completed = _finalize(timestampMs, settings);
      _beginCandidate(result);
      return NoteSegmentationUpdate(finalized: completed);
    }
    _silenceStart = null;
    if (_active != null) {
      final centsApart = _centsBetween(
        result.frequencyHz,
        _active!.frequencyHz,
      );
      if (centsApart.abs() <= settings.pitchToleranceCents) {
        _clearCandidate();
        _active = _active!.copyWith(
          endTimeMs: timestampMs,
          frequencyHz:
              (_active!.frequencyHz * 0.85) + (result.frequencyHz * 0.15),
          confidence: math.max(_active!.confidence, result.confidence),
        );
        return NoteSegmentationUpdate(active: _active);
      }
      if (_candidateMidi == null ||
          _centsBetween(result.frequencyHz, _candidateFrequency).abs() >
              settings.pitchToleranceCents) {
        _beginCandidate(result);
        return NoteSegmentationUpdate(active: _active);
      }
      _addCandidateFrame(result);
      if (timestampMs - _candidateStart! < settings.pitchStabilityMs) {
        return NoteSegmentationUpdate(active: _active);
      }
      final transitionStart = _candidateStart!;
      final candidateMidi = _candidateMidi!;
      final candidateFrequency = _candidateFrequency;
      final candidateConfidence = _candidateConfidence;
      final completed = _finalize(transitionStart, settings);
      _active = RawNoteEvent(
        startTimeMs: transitionStart,
        endTimeMs: timestampMs,
        frequencyHz: candidateFrequency,
        midiPitch: candidateMidi,
        confidence: candidateConfidence,
      );
      _clearCandidate();
      return NoteSegmentationUpdate(active: _active, finalized: completed);
    }

    if (_candidateMidi == null ||
        _centsBetween(result.frequencyHz, _candidateFrequency).abs() >
            settings.pitchToleranceCents) {
      _beginCandidate(result);
      return const NoteSegmentationUpdate();
    }

    _addCandidateFrame(result);
    if (timestampMs - _candidateStart! >= settings.pitchStabilityMs) {
      _active = RawNoteEvent(
        startTimeMs: _candidateStart!,
        endTimeMs: timestampMs,
        frequencyHz: _candidateFrequency,
        midiPitch: _candidateMidi!,
        confidence: _candidateConfidence,
      );
      _clearCandidate();
      return NoteSegmentationUpdate(active: _active);
    }
    return const NoteSegmentationUpdate();
  }

  RawNoteEvent? finish(int timestampMs, VoiceDetectionSettings settings) {
    return _finalize(timestampMs, settings);
  }

  void reset() {
    _clearCandidate();
    _silenceStart = null;
    _active = null;
  }

  void _beginCandidate(PitchDetectionResult result) {
    _candidateMidi = result.midiNote;
    _candidateStart = result.timestampMs;
    _candidateFrequency = result.frequencyHz;
    _candidateConfidence = result.confidence;
    _candidateFrames = 1;
  }

  void _addCandidateFrame(PitchDetectionResult result) {
    _candidateFrames++;
    _candidateFrequency =
        (_candidateFrequency * (_candidateFrames - 1) + result.frequencyHz) /
        _candidateFrames;
    _candidateConfidence = math.max(_candidateConfidence, result.confidence);
  }

  void _clearCandidate() {
    _candidateMidi = null;
    _candidateStart = null;
    _candidateFrames = 0;
  }

  RawNoteEvent? _finalize(int endTime, VoiceDetectionSettings settings) {
    final completed = _active?.copyWith(endTimeMs: endTime);
    _active = null;
    _silenceStart = null;
    if (completed == null ||
        completed.durationMs < settings.minimumNoteDurationMs) {
      return null;
    }
    return completed;
  }

  double _centsBetween(double a, double b) => 1200 * math.log(a / b) / math.ln2;
}
