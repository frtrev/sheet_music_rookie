import '../models/measure.dart';
import '../models/musical_note.dart';
import '../models/raw_note_event.dart';
import '../models/composition.dart';
import 'rhythm_quantizer.dart';

class MeasureBuilder {
  const MeasureBuilder({this.quantizer = const RhythmQuantizer()});
  final RhythmQuantizer quantizer;

  List<Measure> build(
    List<RawNoteEvent> events,
    int tempoBpm,
    int beatsPerMeasure, {
    int octaveTranspositionSemitones = 0,
    KeySignature keySignature = KeySignature.cMajor,
  }) {
    final capacity = beatsPerMeasure * 480;
    final notesByMeasure = <List<MusicalNote>>[[]];
    var measureIndex = 0;
    var cursor = 0;

    for (final indexedEvent in events.indexed) {
      final (sourceEventIndex, event) = indexedEvent;
      final tiedFromPrevious =
          sourceEventIndex > 0 && events[sourceEventIndex - 1].tieToNext;
      var remaining = quantizer.quantizeDuration(event.durationMs, tempoBpm);
      var firstPart = true;
      while (remaining > 0) {
        if (cursor == capacity) {
          measureIndex++;
          cursor = 0;
          notesByMeasure.add([]);
        }
        final available = capacity - cursor;
        final measurePart = remaining < available ? remaining : available;
        for (final duration in _decomposeDuration(measurePart)) {
          notesByMeasure[measureIndex].add(
            MusicalNote(
              // Octave-clef markings describe sounding pitch relative to the
              // written note. Convert captured/sounding pitch back to its
              // written staff position.
              midiPitch: (event.midiPitch - octaveTranspositionSemitones).clamp(
                0,
                127,
              ),
              startTick: cursor,
              durationTicks: duration,
              sourceEventIndex: sourceEventIndex,
              accidental: event.isRest
                  ? NoteAccidental.none
                  : firstPart
                  ? event.accidental
                  : NoteAccidental.none,
              flatSpelling:
                  !event.isRest &&
                  (event.accidental == NoteAccidental.flat ||
                      (event.accidental == NoteAccidental.automatic &&
                          keySignature.accidentalCount < 0 &&
                          const {1, 3, 6, 8, 10}.contains(
                            (event.midiPitch - octaveTranspositionSemitones) %
                                12,
                          ))),
              isRest: event.isRest,
              tieFromPrevious:
                  !event.isRest && (!firstPart || tiedFromPrevious),
              tieToNext:
                  !event.isRest &&
                  (remaining > duration ||
                      (remaining == duration && event.tieToNext)),
            ),
          );
          cursor += duration;
          remaining -= duration;
          firstPart = false;
        }
      }
    }
    if (cursor == capacity) {
      notesByMeasure.add([]);
    }
    return [
      for (var index = 0; index < notesByMeasure.length; index++)
        Measure(
          index: index,
          notes: _applyMeasureAccidentals(notesByMeasure[index], keySignature),
        ),
    ];
  }

  List<MusicalNote> _applyMeasureAccidentals(
    List<MusicalNote> notes,
    KeySignature keySignature,
  ) {
    final activeAlterations = <int, int>{};
    final result = <MusicalNote>[];
    for (final note in notes) {
      if (note.isRest) {
        result.add(note.copyWith(accidental: NoteAccidental.none));
        continue;
      }
      if (note.accidental == NoteAccidental.none) {
        result.add(note);
        continue;
      }

      final pitchClass = note.midiPitch % 12;
      final blackKey = const {1, 3, 6, 8, 10}.contains(pitchClass);
      final flatSpelling = note.flatSpelling && blackKey;
      final naturalPitchClass = blackKey
          ? (flatSpelling ? (pitchClass + 1) % 12 : (pitchClass + 11) % 12)
          : pitchClass;
      const degreeForPitchClass = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
      final staffKey =
          (note.midiPitch ~/ 12) * 7 + degreeForPitchClass[naturalPitchClass];
      final alteration = switch (note.accidental) {
        NoteAccidental.flat => -1,
        NoteAccidental.sharp => 1,
        NoteAccidental.natural => 0,
        NoteAccidental.automatic when blackKey => flatSpelling ? -1 : 1,
        NoteAccidental.automatic => keySignature.alterationForNaturalPitchClass(
          naturalPitchClass,
        ),
        NoteAccidental.none => 0,
      };
      final previous =
          activeAlterations[staffKey] ??
          keySignature.alterationForNaturalPitchClass(naturalPitchClass);
      final display = switch (alteration) {
        _ when alteration == previous => NoteAccidental.none,
        -1 => NoteAccidental.flat,
        0 => NoteAccidental.natural,
        _ => NoteAccidental.sharp,
      };
      activeAlterations[staffKey] = alteration;
      result.add(
        note.copyWith(accidental: display, flatSpelling: flatSpelling),
      );
    }
    return result;
  }

  List<int> _decomposeDuration(int ticks) {
    final parts = <int>[];
    var remaining = ticks;
    for (final value in NoteValue.values.reversed) {
      while (remaining >= value.ticks) {
        parts.add(value.ticks);
        remaining -= value.ticks;
      }
    }
    assert(remaining == 0, 'Duration must align to a sixteenth-note tick.');
    return parts;
  }
}
