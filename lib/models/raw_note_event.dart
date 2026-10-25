import 'note_lyric.dart';
import 'musical_note.dart';

class RawNoteEvent {
  const RawNoteEvent({
    required this.startTimeMs,
    required this.endTimeMs,
    required this.frequencyHz,
    required this.midiPitch,
    required this.confidence,
    this.accidental = NoteAccidental.automatic,
    this.isRest = false,
    this.tieToNext = false,
    this.lyrics = const [],
  });

  final int startTimeMs;
  final int endTimeMs;
  final double frequencyHz;
  final int midiPitch;
  final double confidence;
  final NoteAccidental accidental;
  final bool isRest;
  final bool tieToNext;
  final List<NoteLyric> lyrics;

  int get durationMs => endTimeMs - startTimeMs;

  RawNoteEvent copyWith({
    int? endTimeMs,
    double? frequencyHz,
    double? confidence,
    int? midiPitch,
    NoteAccidental? accidental,
    bool? isRest,
    bool? tieToNext,
  }) {
    return RawNoteEvent(
      lyrics: lyrics,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      midiPitch: midiPitch ?? this.midiPitch,
      confidence: confidence ?? this.confidence,
      accidental: accidental ?? this.accidental,
      isRest: isRest ?? this.isRest,
      tieToNext: tieToNext ?? this.tieToNext,
    );
  }
}
