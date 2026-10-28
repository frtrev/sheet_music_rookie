import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../models/composition.dart';
import '../models/phrase_draft.dart';
import '../models/musical_note.dart';
import '../models/measure.dart';
import '../models/note_lyric.dart';
import 'rest_symbol.dart';

class _LayoutCache {
  final widths = <int, double>{};
  final offsets = <double>[ScoreLayout.left];
  List<String>? lines;
  double? lyricsTop;
  double? height;
  List<({int tick, double x})>? cursorAnchors;
}

final _measureBarlines = Expando<List<XmlElement>>();
List<XmlElement> _barlines(Measure measure) => _measureBarlines[measure] ??= [
  for (final xml in measure.barlines) XmlDocument.parse(xml).rootElement,
];

final _lyricText = Expando<TextPainter>();
TextPainter _lyricPainter(NoteLyric lyric) =>
    _lyricText[lyric] ??= (TextPainter(
      text: TextSpan(
        text: lyric.text,
        style: const TextStyle(fontSize: 14, color: Color(0xff10254f)),
      ),
      textDirection: TextDirection.ltr,
    )..layout());

class ScoreLayout {
  static const measureWidth = 250.0;
  static const lineGap = 14.0;
  static const staffTop = 96.0;
  static const left = 72.0;

  static final _layouts = Expando<_LayoutCache>();
  static _LayoutCache _cache(Composition composition) =>
      _layouts[composition] ??= _LayoutCache();

  static double widthFor(Composition composition, int index) =>
      _cache(composition).widths
          .putIfAbsent(index, () => _computeWidth(composition, index));

  static double _computeWidth(Composition composition, int index) {
    if (index >= composition.measures.length) return measureWidth;
    final measure = composition.measures[index];
    var longest = 0.0;
    var gap = composition.measureCapacityTicks(index);
    for (final (i, note) in measure.notes.indexed) {
      if (note.lyrics.isEmpty) continue;
      for (final lyric in note.lyrics) {
        final painter = _lyricPainter(lyric);
        longest = math.max(longest, painter.width);
      }
      final next = i + 1 < measure.notes.length
          ? measure.notes[i + 1].startTick
          : composition.measureCapacityTicks(index);
      gap = math.min(gap, math.max(1, next - note.startTick));
    }
    if (longest == 0) return measureWidth;
    return math.max(
      measureWidth,
      contentStart(composition, index) +
          30 +
          (longest + 14) * composition.measureCapacityTicks(index) / gap,
    );
  }

  static double measureLeft(Composition composition, int index) {
    final offsets = _cache(composition).offsets;
    while (offsets.length <= index) {
      offsets.add(offsets.last + widthFor(composition, offsets.length - 1));
    }
    return offsets[index];
  }

  static List<String> lyricLines(Composition composition) =>
      _cache(composition).lines ??= _computeLyricLines(composition);

  static List<String> _computeLyricLines(Composition composition) {
    final lines = composition.measures
        .expand((m) => m.notes)
        .expand((n) => n.lyrics)
        .map((l) => l.number)
        .toSet()
        .toList();
    lines.sort((a, b) {
      final x = int.tryParse(a);
      final y = int.tryParse(b);
      return x != null && y != null ? x.compareTo(y) : a.compareTo(b);
    });
    return lines;
  }

  static double lyricsTop(Composition composition) =>
      _cache(composition).lyricsTop ??= _computeLyricsTop(composition);

  static double _computeLyricsTop(Composition composition) {
    var top = 202.0;
    for (final measure in composition.measures) {
      for (final note in measure.notes.where((n) => !n.isRest)) {
        top = math.max(
          top,
          noteCenter(composition, measure.index, note).dy + 48,
        );
      }
    }
    return top;
  }

  static double height(Composition composition) =>
      _cache(composition).height ??= _computeHeight(composition);

  static double _computeHeight(Composition composition) {
    final lines = lyricLines(composition);
    return lines.isEmpty
        ? 250
        : math.max(250, lyricsTop(composition) + lines.length * 26 + 24);
  }

  static double contentStart(Composition composition, int measureIndex) {
    if (measureIndex == 0) {
      return 54 + composition.keySignature.accidentalCount.abs() * 7.5;
    }
    final measure = composition.measures[measureIndex];
    final previous = composition.measures[measureIndex - 1];
    final changed =
        measure.effectiveBeats(composition.beatsPerMeasure) !=
            previous.effectiveBeats(composition.beatsPerMeasure) ||
        measure.effectiveBeatUnit(composition.beatUnit) !=
            previous.effectiveBeatUnit(composition.beatUnit);
    final hasLyrics = measure.notes.any((n) => n.lyrics.isNotEmpty);
    return changed ? (hasLyrics ? 54 : 44) : (hasLyrics ? 40 : 14);
  }

  static Offset noteCenter(
    Composition composition,
    int measureIndex,
    MusicalNote note,
  ) {
    final start = contentStart(composition, measureIndex);
    final usable = widthFor(composition, measureIndex) - start - 14;
    final x =
        measureLeft(composition, measureIndex) +
        start +
        usable *
            note.startTick /
            composition.measureCapacityTicks(measureIndex);
    final bottom = staffTop + 4 * lineGap;
    final y = note.isRest
        ? staffTop + 2 * lineGap
        : bottom -
              staffStep(
                    composition.clef,
                    note.midiPitch,
                    accidental: note.accidental,
                    flatSpelling: note.flatSpelling,
                  ) *
                  (lineGap / 2);
    return Offset(x, y);
  }

  /// Horizontal lyric space, ending before the next note or the barline.
  static Rect lyricBounds(
    Composition composition,
    int measureIndex,
    int noteIndex,
  ) {
    final notes = composition.measures[measureIndex].notes;
    final center = noteCenter(composition, measureIndex, notes[noteIndex]).dx;
    final left = math.max(
      measureLeft(composition, measureIndex) + 4,
      center - 12,
    );
    final right = noteIndex + 1 < notes.length
        ? noteCenter(composition, measureIndex, notes[noteIndex + 1]).dx - 16
        : measureLeft(composition, measureIndex + 1) - 4;
    return Rect.fromLTWH(left, 0, math.max(0, right - left), 0);
  }

  static Offset? tieTarget(
    Composition composition,
    int measureIndex,
    MusicalNote note,
  ) {
    if (!note.tieToNext || note.isRest) return null;
    final notes = composition.measures[measureIndex].notes;
    final index = notes.indexOf(note);
    if (index < 0) return null;
    final targetMeasure = index + 1 < notes.length
        ? measureIndex
        : measureIndex + 1;
    if (targetMeasure >= composition.measures.length) return null;
    final targetNotes = composition.measures[targetMeasure].notes;
    if (targetNotes.isEmpty) return null;
    final target = targetNotes[targetMeasure == measureIndex ? index + 1 : 0];
    if (!target.tieFromPrevious ||
        target.isRest ||
        target.midiPitch != note.midiPitch) {
      return null;
    }
    return noteCenter(composition, targetMeasure, target);
  }

  static int staffStep(
    ClefType clef,
    int midi, {
    NoteAccidental accidental = NoteAccidental.automatic,
    bool flatSpelling = false,
  }) {
    const degreeForPitchClass = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
    final pitchClass = midi % 12;
    final flatAdjustment =
        (flatSpelling || accidental == NoteAccidental.flat) &&
            const {1, 3, 6, 8, 10}.contains(pitchClass)
        ? 1
        : 0;
    final diatonic =
        (midi ~/ 12 - 1) * 7 + degreeForPitchClass[pitchClass] + flatAdjustment;
    final bottomLine = clef.bottomLineDiatonic;
    return diatonic - bottomLine;
  }

  static int ticksAt(Duration position, int tempoBpm) =>
      (position.inMicroseconds * tempoBpm * 480 / 60000000).round();

  static Duration durationAt(int ticks, int tempoBpm) =>
      Duration(microseconds: (ticks * 60000000 / (tempoBpm * 480)).round());

  static int scoreEndTick(Composition composition) {
    var endTick = 0;
    for (final measure in composition.measures) {
      for (final note in measure.notes) {
        endTick = math.max(
          endTick,
          composition.measureStartTick(measure.index) +
              note.startTick +
              note.durationTicks,
        );
      }
    }
    return endTick;
  }

  static int editableEndTick(Composition composition) =>
      composition.editableEndTick;

  static int tickAtX(Composition composition, double x) {
    var rawMeasureIndex = 0;
    while (rawMeasureIndex + 1 < composition.measures.length &&
        x >= measureLeft(composition, rawMeasureIndex + 1)) {
      rawMeasureIndex++;
    }
    final measureIndex = rawMeasureIndex
        .clamp(0, math.max(0, composition.measures.length - 1))
        .toInt();
    final capacity = composition.measureCapacityTicks(measureIndex);
    final start = contentStart(composition, measureIndex);
    final usable = widthFor(composition, measureIndex) - start - 14;
    final localX = x - measureLeft(composition, measureIndex) - start;
    final unsnappedTick = (localX / usable * capacity).round();
    final localTick = ((unsnappedTick / 120).round() * 120)
        .clamp(0, capacity)
        .toInt();
    return (composition.measureStartTick(measureIndex) + localTick)
        .clamp(0, editableEndTick(composition))
        .toInt();
  }

  static double cursorX(Composition composition, int absoluteTick) {
    final boundedTick = absoluteTick
        .clamp(0, editableEndTick(composition))
        .toInt();
    final maxMeasureIndex = math.max(0, composition.measures.length - 1);
    final measureIndex = composition
        .measureIndexAtTick(boundedTick)
        .clamp(0, maxMeasureIndex);
    final capacity = composition.measureCapacityTicks(measureIndex);
    final localTick = (boundedTick - composition.measureStartTick(measureIndex))
        .clamp(0, capacity);
    final start = contentStart(composition, measureIndex);
    final usable = widthFor(composition, measureIndex) - start - 14;
    return measureLeft(composition, measureIndex) +
        start +
        usable * localTick / capacity;
  }

  /// Playback traverses the space between note onsets, including the padding
  /// around barlines. The editing cursor keeps its original tick hit-testing.
  static double playbackCursorX(Composition composition, int absoluteTick) {
    if (lyricLines(composition).isEmpty) {
      return cursorX(composition, absoluteTick);
    }
    final anchors = _cache(composition).cursorAnchors ??= _cursorAnchors(
      composition,
    );
    if (anchors.length < 2) return cursorX(composition, absoluteTick);
    if (absoluteTick <= anchors.first.tick) return anchors.first.x;
    if (absoluteTick >= anchors.last.tick) return anchors.last.x;
    var low = 0;
    var high = anchors.length - 1;
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      if (anchors[middle].tick <= absoluteTick) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final start = anchors[low];
    final end = anchors[high];
    final fraction = (absoluteTick - start.tick) / (end.tick - start.tick);
    return start.x + (end.x - start.x) * fraction;
  }

  static List<({int tick, double x})> _cursorAnchors(Composition composition) {
    final positions = <int, double>{};
    for (final measure in composition.measures) {
      final start = composition.measureStartTick(measure.index);
      for (final note in measure.notes) {
        positions[start + note.startTick] = noteCenter(
          composition,
          measure.index,
          note,
        ).dx;
      }
    }
    final end = scoreEndTick(composition);
    positions.putIfAbsent(end, () => cursorX(composition, end));
    final ticks = positions.keys.toList()..sort();
    return [for (final tick in ticks) (tick: tick, x: positions[tick]!)];
  }

  static double? scrollOffsetToRevealCursor({
    required double cursorX,
    required double currentOffset,
    required double viewportWidth,
    required double maxScrollExtent,
    double leftMargin = 28,
    double rightMargin = 44,
  }) {
    final leftEdge = currentOffset + leftMargin;
    final rightEdge = currentOffset + viewportWidth - rightMargin;
    if (cursorX > rightEdge) {
      return (cursorX - viewportWidth + rightMargin)
          .clamp(0.0, maxScrollExtent)
          .toDouble();
    }
    if (cursorX < leftEdge) {
      return (cursorX - leftMargin).clamp(0.0, maxScrollExtent).toDouble();
    }
    return null;
  }

  static double? scrollOffsetToFollowCursor({
    required double cursorX,
    required double currentOffset,
    required double viewportWidth,
    required double maxScrollExtent,
    required double followFraction,
    double leftMargin = 28,
  }) {
    final anchor = viewportWidth * followFraction.clamp(.1, .9);
    final viewportX = cursorX - currentOffset;
    if (viewportX <= anchor && viewportX >= leftMargin) return null;
    return (cursorX - anchor).clamp(0.0, maxScrollExtent).toDouble();
  }
}

class ScoreView extends StatelessWidget {
  const ScoreView({
    super.key,
    required this.composition,
    this.scrollController,
    this.selectedEventIndex,
    this.selectedTick,
    this.previewStartTick,
    this.previewEndTick,
    this.playbackPosition = Duration.zero,
    this.showPlaybackCursor = false,
    this.practiceTargetTick,
    this.practiceProgress,
    this.cursorFollowFraction = .40,
    this.onCursorMoved,
    this.pitchTrace = const [],
  });

  final Composition composition;
  final ScrollController? scrollController;
  final int? selectedEventIndex;
  final int? selectedTick;
  final int? previewStartTick;
  final int? previewEndTick;
  final Duration playbackPosition;
  final bool showPlaybackCursor;
  final int? practiceTargetTick;
  final ValueListenable<double>? practiceProgress;
  final double cursorFollowFraction;
  final ValueChanged<Duration>? onCursorMoved;
  final List<PitchTracePoint> pitchTrace;

  @override
  Widget build(BuildContext context) {
    final displayedMeasures = math.max(3, composition.measures.length);
    final width =
        ScoreLayout.measureLeft(composition, displayedMeasures) +
        MediaQuery.sizeOf(context).width * (1 - cursorFollowFraction);
    return SingleChildScrollView(
      child: SizedBox(
        height: ScoreLayout.height(composition),
        child: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onCursorMoved == null
                  ? null
                  : (details) => _handleTap(details.localPosition),
              child: SizedBox(
                width: width,
                height: ScoreLayout.height(composition),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        isComplex: true,
                        painter: ScorePainter(
                          composition,
                          selectedEventIndex: selectedEventIndex,
                          selectedTick: selectedTick,
                          previewStartTick: previewStartTick,
                          previewEndTick: previewEndTick,
                        ),
                      ),
                    ),
                    if (pitchTrace.isNotEmpty)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: PitchTracePainter(composition, pitchTrace),
                        ),
                      ),
                    if (showPlaybackCursor)
                      IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            willChange: true,
                            painter: ScoreCursorPainter(
                              composition,
                              playbackPosition,
                            ),
                          ),
                        ),
                      ),
                    if (practiceTargetTick != null && practiceProgress != null)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: PracticeProgressPainter(
                            composition,
                            targetTick: practiceTargetTick!,
                            progress: practiceProgress!,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap(Offset position) {
    final ticks = ScoreLayout.tickAtX(composition, position.dx);
    onCursorMoved?.call(ScoreLayout.durationAt(ticks, composition.tempoBpm));
  }
}

class PitchTracePainter extends CustomPainter {
  PitchTracePainter(this.composition, this.points);
  final Composition composition;
  final List<PitchTracePoint> points;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    var connected = false;
    for (final point in points) {
      if (point.midi == null) {
        connected = false;
        continue;
      }
      final written = point.midi! - composition.octaveRange.semitones;
      final lower = written.floor().clamp(0, 126);
      final fraction = written - lower;
      final step =
          ScoreLayout.staffStep(composition.clef, lower) * (1 - fraction) +
          ScoreLayout.staffStep(composition.clef, lower + 1) * fraction;
      final x = ScoreLayout.playbackCursorX(composition, point.tick);
      final y =
          ScoreLayout.staffTop +
          4 * ScoreLayout.lineGap -
          step * ScoreLayout.lineGap / 2;
      if (connected) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
      }
      connected = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff00a8d6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant PitchTracePainter old) =>
      old.composition != composition || old.points != points;
}

/// The moving cursor repaints independently of the staff and lyric layer.
class ScoreCursorPainter extends CustomPainter {
  ScoreCursorPainter(this.composition, this.position);
  final Composition composition;
  final Duration position;

  @override
  void paint(Canvas canvas, Size size) {
    ScorePainter(
      composition,
      playbackPosition: position,
    )._drawPlaybackCursor(canvas);
  }

  @override
  bool shouldRepaint(covariant ScoreCursorPainter oldDelegate) =>
      oldDelegate.composition != composition ||
      oldDelegate.position != position;
}

class PracticeProgressPainter extends CustomPainter {
  PracticeProgressPainter(
    this.composition, {
    required this.targetTick,
    required this.progress,
  }) : super(repaint: progress);

  final Composition composition;
  final int targetTick;
  final ValueListenable<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = _targetCenter();
    if (center == null) return;
    const radius = 16.0;
    final circle = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x4439b86d)
        ..style = PaintingStyle.fill,
    );

    final amount = progress.value.clamp(0.0, 1.0).toDouble();
    if (amount > 0) {
      final fill = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(circle, -math.pi / 2, math.pi * 2 * amount, false)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..color = const Color(0x99318f58)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xaa318f58)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  Offset? _targetCenter() {
    for (final measure in composition.measures) {
      for (final note in measure.notes) {
        final absoluteTick =
            composition.measureStartTick(measure.index) + note.startTick;
        if (!note.isRest && absoluteTick == targetTick) {
          return ScoreLayout.noteCenter(composition, measure.index, note);
        }
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant PracticeProgressPainter oldDelegate) =>
      oldDelegate.composition != composition ||
      oldDelegate.targetTick != targetTick ||
      oldDelegate.progress != progress;
}

class ScorePainter extends CustomPainter {
  ScorePainter(
    this.composition, {
    this.selectedEventIndex,
    this.selectedTick,
    this.previewStartTick,
    this.previewEndTick,
    this.playbackPosition = Duration.zero,
    this.showPlaybackCursor = false,
  });
  final Composition composition;
  final int? selectedEventIndex;
  final int? selectedTick;
  final int? previewStartTick;
  final int? previewEndTick;
  final Duration playbackPosition;
  final bool showPlaybackCursor;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xff242722)
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke;
    final displayedMeasures = math.max(3, composition.measures.length);
    final staffEnd = ScoreLayout.measureLeft(composition, displayedMeasures);

    for (var line = 0; line < 5; line++) {
      final y = ScoreLayout.staffTop + line * ScoreLayout.lineGap;
      canvas.drawLine(Offset(22, y), Offset(staffEnd, y), ink);
    }
    canvas.drawLine(
      const Offset(22, ScoreLayout.staffTop),
      const Offset(22, ScoreLayout.staffTop + 4 * ScoreLayout.lineGap),
      ink..strokeWidth = 2,
    );
    for (var measure = 0; measure <= displayedMeasures; measure++) {
      final x = ScoreLayout.measureLeft(composition, measure);
      canvas.drawLine(
        Offset(x, ScoreLayout.staffTop),
        Offset(x, ScoreLayout.staffTop + 4 * ScoreLayout.lineGap),
        ink..strokeWidth = measure == displayedMeasures ? 3 : 1.2,
      );
    }

    _drawText(
      canvas,
      composition.clef.symbol,
      Offset(
        28,
        composition.clef == ClefType.tenor
            ? 68
            : composition.clef == ClefType.alto
            ? 82
            : 75,
      ),
      54,
    );
    if (composition.octaveRange != OctaveRange.standard) {
      final above = composition.octaveRange.semitones > 0;
      _drawText(
        canvas,
        composition.octaveRange.notationLabel.startsWith('15') ? '15' : '8',
        Offset(40, above ? 68 : 151),
        13,
        weight: FontWeight.w700,
      );
    }
    final firstMeasure = composition.measures.isEmpty
        ? null
        : composition.measures.first;
    _drawText(
      canvas,
      '${firstMeasure?.effectiveBeats(composition.beatsPerMeasure) ?? composition.beatsPerMeasure}\n'
      '${firstMeasure?.effectiveBeatUnit(composition.beatUnit) ?? composition.beatUnit}',
      const Offset(72, 93),
      22,
      height: .72,
    );
    _drawText(
      canvas,
      '♩ = ${composition.tempoBpm}',
      const Offset(24, 30),
      17,
      weight: FontWeight.w600,
    );
    _drawText(
      canvas,
      composition.keySignature.name,
      const Offset(132, 45),
      13,
      color: const Color(0xff5e625c),
    );
    _drawKeySignature(canvas);

    _drawRepeatMarks(canvas);
    final selectedSources = _selectedSourceEvents();
    for (final measure in composition.measures) {
      if (measure.index > 0) {
        final previous = composition.measures[measure.index - 1];
        final beats = measure.effectiveBeats(composition.beatsPerMeasure);
        final unit = measure.effectiveBeatUnit(composition.beatUnit);
        if (beats != previous.effectiveBeats(composition.beatsPerMeasure) ||
            unit != previous.effectiveBeatUnit(composition.beatUnit)) {
          _drawText(
            canvas,
            '$beats\n$unit',
            Offset(ScoreLayout.measureLeft(composition, measure.index) + 7, 93),
            19,
            height: .72,
          );
        }
      }
      for (final note in measure.notes) {
        _drawNote(canvas, measure.index, note, ink, selectedSources);
      }
      _drawText(
        canvas,
        '${measure.index + 1}',
        Offset(ScoreLayout.measureLeft(composition, measure.index) + 6, 174),
        11,
        color: const Color(0xff777a74),
      );
    }
    _drawLyrics(canvas);
    if (showPlaybackCursor) _drawPlaybackCursor(canvas);
  }

  void _drawRepeatMarks(Canvas canvas) {
    var inEnding = false;
    final paint = Paint()
      ..color = const Color(0xff10254f)
      ..strokeWidth = 1.5;
    for (final measure in composition.measures) {
      final left = ScoreLayout.measureLeft(composition, measure.index);
      final right = ScoreLayout.measureLeft(composition, measure.index + 1);
      var closesEnding = false;
      for (final bar in _barlines(measure)) {
        for (final ending in bar.findElements('ending')) {
          if (ending.getAttribute('type') == 'start') {
            inEnding = true;
            _drawText(
              canvas,
              '${ending.getAttribute('number') ?? ''}.',
              Offset(left + 8, 50),
              12,
              weight: FontWeight.w600,
            );
            canvas.drawLine(Offset(left + 3, 70), Offset(left + 3, 80), paint);
          } else {
            closesEnding = true;
            if (ending.getAttribute('type') == 'stop') {
              canvas.drawLine(
                Offset(right - 3, 70),
                Offset(right - 3, 80),
                paint,
              );
            }
          }
        }
        for (final repeat in bar.findElements('repeat')) {
          final forward = repeat.getAttribute('direction') == 'forward';
          final x = forward ? left + 4 : right - 4;
          canvas.drawLine(
            Offset(x, ScoreLayout.staffTop),
            Offset(x, ScoreLayout.staffTop + 56),
            paint..strokeWidth = 3,
          );
          final thin = x + (forward ? 5 : -5);
          canvas.drawLine(
            Offset(thin, ScoreLayout.staffTop),
            Offset(thin, ScoreLayout.staffTop + 56),
            paint..strokeWidth = 1.2,
          );
          final dots = x + (forward ? 11 : -11);
          for (final y in [
            ScoreLayout.staffTop + 21,
            ScoreLayout.staffTop + 35,
          ]) {
            canvas.drawCircle(Offset(dots, y), 2.5, paint);
          }
        }
      }
      if (inEnding) {
        canvas.drawLine(
          Offset(left + 3, 70),
          Offset(right - 3, 70),
          paint..strokeWidth = 1.2,
        );
      }
      if (closesEnding) inEnding = false;
    }
  }

  void _drawLyrics(Canvas canvas) {
    final lines = ScoreLayout.lyricLines(composition);
    final top = ScoreLayout.lyricsTop(composition);
    for (final (row, line) in lines.indexed) {
      _drawText(
        canvas,
        line,
        Offset(28, top + row * 26),
        12,
        color: const Color(0xff566784),
      );
    }
    for (final measure in composition.measures) {
      for (final (index, note) in measure.notes.indexed) {
        final center = ScoreLayout.noteCenter(composition, measure.index, note);
        final nextX = index + 1 < measure.notes.length
            ? ScoreLayout.noteCenter(
                composition,
                measure.index,
                measure.notes[index + 1],
              ).dx
            : ScoreLayout.measureLeft(composition, measure.index + 1);
        final bounds = ScoreLayout.lyricBounds(
          composition,
          measure.index,
          index,
        );
        final available = bounds.width;
        for (final lyric in note.lyrics) {
          final y = top + lines.indexOf(lyric.number) * 26;
          final text = _lyricPainter(lyric);
          final scale = text.width > available ? available / text.width : 1.0;
          final renderedWidth = text.width * scale;
          final left = (center.dx - renderedWidth / 2)
              .clamp(
                bounds.left,
                math.max(bounds.left, bounds.right - renderedWidth),
              )
              .toDouble();
          canvas.save();
          canvas.translate(left, y);
          canvas.scale(scale, 1);
          text.paint(canvas, Offset.zero);
          canvas.restore();
          final end = left + renderedWidth + 3;
          if ((lyric.syllabic == 'begin' || lyric.syllabic == 'middle') &&
              nextX - end > 8) {
            _drawText(canvas, '−', Offset((end + nextX - 5) / 2 - 4, y), 12);
          }
          if (lyric.extendsNote && nextX - end > 5) {
            canvas.drawLine(
              Offset(end, y + 17),
              Offset(nextX - 5, y + 17),
              Paint()
                ..color = const Color(0xff566784)
                ..strokeWidth = 1,
            );
          }
        }
      }
    }
  }

  Set<int> _selectedSourceEvents() => {?selectedEventIndex};

  void _drawNote(
    Canvas canvas,
    int measureIndex,
    MusicalNote note,
    Paint ink,
    Set<int> selectedSources,
  ) {
    final center = ScoreLayout.noteCenter(composition, measureIndex, note);
    final x = center.dx;
    final y = center.dy;
    final absoluteTick =
        composition.measureStartTick(measureIndex) + note.startTick;
    final preview =
        previewStartTick != null &&
        previewEndTick != null &&
        absoluteTick >= previewStartTick! &&
        absoluteTick < previewEndTick!;
    ink.color = preview ? const Color(0xffa0a8b8) : const Color(0xff242722);
    final step = ScoreLayout.staffStep(
      composition.clef,
      note.midiPitch,
      accidental: note.accidental,
      flatSpelling: note.flatSpelling,
    );

    final noteTick =
        composition.measureStartTick(measureIndex) + note.startTick;
    final selected = selectedTick == null
        ? selectedSources.contains(note.sourceEventIndex)
        : selectedTick! >= noteTick &&
              selectedTick! < noteTick + note.durationTicks;
    if (selected) {
      canvas.drawCircle(
        center,
        15,
        Paint()
          ..color = const Color(0x55315b4c)
          ..style = PaintingStyle.fill,
      );
    }

    if (note.isRest) {
      _drawRest(canvas, note, x, y);
      return;
    }

    final accidental = switch (note.accidental) {
      NoteAccidental.sharp => '♯',
      NoteAccidental.flat => '♭',
      NoteAccidental.natural => '♮',
      NoteAccidental.automatic
          when const {1, 3, 6, 8, 10}.contains(note.midiPitch % 12) =>
        '♯',
      _ => null,
    };
    if (accidental != null) {
      _drawText(canvas, accidental, Offset(x - 22, y - 13), 18);
    }

    final baseTicks = note.value.baseTicks;
    final hollowHead = baseTicks >= 960;
    ink
      ..strokeWidth = 1.5
      ..style = hollowHead ? PaintingStyle.stroke : PaintingStyle.fill;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.25);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 14, height: 9),
      ink,
    );
    canvas.restore();

    _drawLedgerLines(canvas, x, step, ink);
    if (baseTicks < 1920) {
      ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final stemUp = step < 4;
      final stemX = x + (stemUp ? 6 : -6);
      final stemEnd = y + (stemUp ? -38 : 38);
      canvas.drawLine(Offset(stemX, y), Offset(stemX, stemEnd), ink);
      final flags = baseTicks <= 120 ? 2 : (baseTicks <= 240 ? 1 : 0);
      for (var flag = 0; flag < flags; flag++) {
        final direction = stemUp ? 1.0 : -1.0;
        final start = Offset(stemX, stemEnd + direction * flag * 7);
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(
            start.dx + 12,
            start.dy + direction * 7,
            start.dx + 8,
            start.dy + direction * 17,
          );
        canvas.drawPath(path, ink);
      }
    }
    if (note.value.isDotted) {
      canvas.drawCircle(
        Offset(x + 13, y - 1),
        2.2,
        ink
          ..style = PaintingStyle.fill
          ..strokeWidth = 1,
      );
    }
    final target = ScoreLayout.tieTarget(composition, measureIndex, note);
    if (target != null) {
      final span = target.dx - x;
      final arch = (span * .12).clamp(10.0, 28.0);
      final tie = Path()
        ..moveTo(x, y + 9)
        ..quadraticBezierTo(
          (x + target.dx) / 2,
          math.max(y, target.dy) + 9 + arch,
          target.dx,
          target.dy + 9,
        );
      canvas.drawPath(
        tie,
        ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _drawKeySignature(Canvas canvas) {
    final count = composition.keySignature.accidentalCount;
    if (count == 0) return;
    const trebleSharps = [8, 5, 9, 6, 3, 7, 4];
    const bassSharps = [6, 3, 7, 4, 1, 5, 2];
    const trebleFlats = [4, 7, 3, 6, 2, 5, 1];
    const bassFlats = [2, 5, 1, 4, 0, 3, -1];
    const altoSharps = [7, 4, 8, 5, 2, 6, 3];
    const altoFlats = [3, 6, 2, 5, 1, 4, 0];
    const tenorSharps = [2, 6, 3, 7, 4, 8, 5];
    const tenorFlats = [5, 8, 4, 7, 3, 6, 2];
    final sharps = count > 0;
    final steps = switch ((composition.clef, sharps)) {
      (ClefType.treble, true) => trebleSharps,
      (ClefType.bass, true) => bassSharps,
      (ClefType.treble, false) => trebleFlats,
      (ClefType.bass, false) => bassFlats,
      (ClefType.alto, true) => altoSharps,
      (ClefType.alto, false) => altoFlats,
      (ClefType.tenor, true) => tenorSharps,
      (ClefType.tenor, false) => tenorFlats,
    };
    final bottom = ScoreLayout.staffTop + 4 * ScoreLayout.lineGap;
    for (var index = 0; index < count.abs(); index++) {
      final y = bottom - steps[index] * (ScoreLayout.lineGap / 2);
      _drawText(
        canvas,
        sharps ? '♯' : '♭',
        Offset(99 + index * 7.5, y - 14),
        18,
      );
    }
  }

  void _drawRest(Canvas canvas, MusicalNote note, double x, double y) {
    drawRestSymbol(canvas, Offset(x, y), note.value.baseTicks, size: 25);
    if (note.value.isDotted) {
      canvas.drawCircle(
        Offset(x + 14, y - 1),
        2.2,
        Paint()
          ..color = const Color(0xff242722)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawLedgerLines(Canvas canvas, double x, int step, Paint ink) {
    ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    if (step < 0) {
      for (var ledger = -2; ledger >= step; ledger -= 2) {
        final y =
            ScoreLayout.staffTop +
            4 * ScoreLayout.lineGap -
            ledger * (ScoreLayout.lineGap / 2);
        canvas.drawLine(Offset(x - 11, y), Offset(x + 11, y), ink);
      }
    } else if (step > 8) {
      for (var ledger = 10; ledger <= step; ledger += 2) {
        final y =
            ScoreLayout.staffTop +
            4 * ScoreLayout.lineGap -
            ledger * (ScoreLayout.lineGap / 2);
        canvas.drawLine(Offset(x - 11, y), Offset(x + 11, y), ink);
      }
    }
  }

  void _drawPlaybackCursor(Canvas canvas) {
    final ticks = ScoreLayout.ticksAt(playbackPosition, composition.tempoBpm);
    final x = ScoreLayout.playbackCursorX(composition, ticks);
    final paint = Paint()
      ..color = const Color(0xffd25b3f)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 76) + Offset(x, 0), Offset(x, 174), paint);
    final marker = Path()
      ..moveTo(x - 6, 72)
      ..lineTo(x + 6, 72)
      ..lineTo(x, 80)
      ..close();
    canvas.drawPath(marker, paint..style = PaintingStyle.fill);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double size, {
    double? height,
    FontWeight? weight,
    Color color = const Color(0xff242722),
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          height: height,
          fontWeight: weight,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant ScorePainter oldDelegate) =>
      oldDelegate.composition != composition ||
      oldDelegate.selectedEventIndex != selectedEventIndex ||
      oldDelegate.selectedTick != selectedTick ||
      oldDelegate.previewStartTick != previewStartTick ||
      oldDelegate.previewEndTick != previewEndTick ||
      oldDelegate.playbackPosition != playbackPosition ||
      oldDelegate.showPlaybackCursor != showPlaybackCursor;
}
