import 'composition.dart';
import 'raw_note_event.dart';

enum PhraseStage { recording, analyzing, review, failed }

class PitchTracePoint {
  const PitchTracePoint(this.tick, this.midi);
  final int tick;
  final double? midi;
}

class PhraseDraft {
  const PhraseDraft({
    required this.stage,
    required this.startTick,
    this.trace = const [],
    this.events = const [],
    this.preview,
    this.endTick,
    this.message,
  });
  final PhraseStage stage;
  final int startTick;
  final int? endTick;
  final List<PitchTracePoint> trace;
  final List<RawNoteEvent> events;
  final Composition? preview;
  final String? message;
}
