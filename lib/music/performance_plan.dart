import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../models/composition.dart';
import '../models/measure.dart';
import '../models/musical_note.dart';

class MeasureVisit {
  const MeasureVisit(this.sourceIndex, this.startTick, this.durationTicks);
  final int sourceIndex;
  final int startTick;
  final int durationTicks;
}

/// One bounded, shared musical itinerary for playback, practice and testing.
/// Written measures remain untouched; repeated visits have their own time.
class PerformancePlan {
  factory PerformancePlan(Composition source) {
    final order = _measureOrder(source.measures);
    var tick = 0;
    final visits = <MeasureVisit>[];
    final measures = <Measure>[];
    var run = 0;
    var previousIndex = -1;
    final sourceCount = source.measures
        .expand((m) => m.notes)
        .fold(0, (n, note) => math.max(n, note.sourceEventIndex + 1));
    for (final index in order) {
      final jumped = previousIndex >= 0 && index != previousIndex + 1;
      if (jumped) run++;
      previousIndex = index;
      final original = source.measures[index];
      final capacity = source.measureCapacityTicks(index);
      visits.add(MeasureVisit(index, tick, capacity));
      measures.add(
        Measure(
          index: measures.length,
          notes: [
            for (final (n, note) in original.notes.indexed)
              MusicalNote(
                midiPitch: note.midiPitch,
                startTick: note.startTick,
                durationTicks: note.durationTicks,
                sourceEventIndex: note.sourceEventIndex < 0
                    ? -1
                    : note.sourceEventIndex + run * sourceCount,
                accidental: note.accidental,
                flatSpelling: note.flatSpelling,
                isRest: note.isRest,
                tieFromPrevious: note.tieFromPrevious && !(jumped && n == 0),
                tieToNext: note.tieToNext,
                lyrics: note.lyrics,
              ),
          ],
          beatsPerMeasure: original.effectiveBeats(source.beatsPerMeasure),
          beatUnit: original.effectiveBeatUnit(source.beatUnit),
        ),
      );
      tick += capacity;
    }
    return PerformancePlan._(
      source,
      source.copyWith(measures: measures),
      visits,
    );
  }
  PerformancePlan._(this.source, this.expanded, this.visits);
  final Composition source;
  final Composition expanded;
  final List<MeasureVisit> visits;

  int sourceTickAt(int tick) {
    if (visits.isEmpty) return 0;
    final visit = visits.lastWhere(
      (v) => tick >= v.startTick,
      orElse: () => visits.first,
    );
    return source.measureStartTick(visit.sourceIndex) +
        (tick - visit.startTick).clamp(0, visit.durationTicks);
  }

  /// Seek to this written position, preferring the current pass when possible.
  int performanceTickAt(int sourceTick, {int? nearTick}) {
    if (visits.isEmpty) return 0;
    final index = source.measureIndexAtTick(sourceTick);
    final local = sourceTick - source.measureStartTick(index);
    final matches = visits.where((v) => v.sourceIndex == index).toList();
    if (matches.isEmpty) return 0;
    final visit = nearTick == null
        ? matches.first
        : matches.reduce(
            (a, b) =>
                (a.startTick + local - nearTick).abs() <=
                    (b.startTick + local - nearTick).abs()
                ? a
                : b,
          );
    return visit.startTick + local.clamp(0, visit.durationTicks);
  }
}

class _Ending {
  _Ending(this.start, this.end, this.passes);
  final int start;
  int end;
  final Set<int> passes;
}

class _Repeat {
  _Repeat(this.start, this.end, this.times);
  final int start;
  final int end;
  final int times;
  final endings = <_Ending>[];
  int get last => endings.isEmpty ? end : math.max(end, endings.last.end);
  int get passes => endings.fold(times, (n, e) => e.passes.fold(n, math.max));
}

Set<int> _passes(String value) {
  final result = <int>{};
  for (final token in value.split(',')) {
    final range = token.trim().split('-');
    final first = int.tryParse(range.first.trim());
    final last = int.tryParse(range.last.trim());
    if (first == null ||
        last == null ||
        first < 1 ||
        last > 32 ||
        last < first) {
      continue;
    }
    for (var n = first; n <= last; n++) {
      result.add(n);
    }
  }
  return result;
}

List<int> _measureOrder(List<Measure> measures) {
  final repeats = <_Repeat>[];
  final starts = <int>[];
  final endings = <_Ending>[];
  _Ending? active;
  for (var i = 0; i < measures.length; i++) {
    for (final xml in measures[i].barlines) {
      final bar = XmlDocument.parse(xml).rootElement;
      for (final ending in bar.findElements('ending')) {
        if (ending.getAttribute('type') == 'start') {
          if (active != null) active.end = math.max(active.start, i - 1);
          active = _Ending(
            i,
            measures.length - 1,
            _passes(ending.getAttribute('number') ?? ''),
          );
          endings.add(active);
        } else if (active != null) {
          active.end = i;
          active = null;
        }
      }
      for (final repeat in bar.findElements('repeat')) {
        if (repeat.getAttribute('direction') == 'forward') {
          starts.add(i);
        } else if (repeat.getAttribute('direction') == 'backward') {
          final start = starts.isEmpty ? 0 : starts.removeLast();
          final times = (int.tryParse(repeat.getAttribute('times') ?? '') ?? 2)
              .clamp(1, 32);
          repeats.add(_Repeat(start, i, times));
        }
      }
    }
  }
  for (final repeat in repeats) {
    // An ending group must include the repeat's closing bar. An isolated
    // number elsewhere is not enough evidence to omit the music.
    final first = endings
        .where(
          (e) =>
              e.start >= repeat.start &&
              e.start <= repeat.end &&
              e.end == repeat.end,
        )
        .firstOrNull;
    if (first == null || !first.passes.contains(1)) continue;
    repeat.endings.add(first);
    var next = repeat.end + 1;
    for (final ending in endings.where((e) => e.start > repeat.end)) {
      if (ending.start != next) break;
      // A new forward repeat begins a new section, not another ending.
      if (repeats.any((r) => r != repeat && r.start == ending.start)) break;
      repeat.endings.add(ending);
      next = ending.end + 1;
    }
  }
  final result = <int>[];
  var operations = 0;
  void visit(int start, int end, {_Repeat? enclosing, int pass = 1}) {
    for (var i = start; i <= end; i++) {
      if (++operations > 100000 || result.length > 20000) {
        throw const FormatException('Repeat sequence is too large.');
      }
      final excluded = enclosing?.endings
          .where((e) => i >= e.start && i <= e.end && !e.passes.contains(pass))
          .firstOrNull;
      if (excluded != null) {
        i = excluded.end;
        continue;
      }
      final nested =
          repeats
              .where((r) => r != enclosing && r.start == i && r.last <= end)
              .toList()
            ..sort((a, b) => b.last.compareTo(a.last));
      if (nested.isNotEmpty) {
        final repeat = nested.first;
        for (var n = 1; n <= repeat.passes; n++) {
          visit(repeat.start, repeat.last, enclosing: repeat, pass: n);
        }
        i = repeat.last;
      } else {
        result.add(i);
      }
    }
  }

  visit(0, measures.length - 1);
  return result;
}
