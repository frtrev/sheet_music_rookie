import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/composition.dart';
import '../models/musical_note.dart';
import 'rest_symbol.dart';

class ScoreLayout {
  static const measureWidth = 250.0;
  static const lineGap = 14.0;
  static const staffTop = 96.0;
  static const left = 72.0;

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
    return changed ? 44 : 14;
  }

  static Offset noteCenter(
    Composition composition,
    int measureIndex,
    MusicalNote note,
  ) {
    final start = contentStart(composition, measureIndex);
    final usable = measureWidth - start - 14;
    final x =
        left +
        measureIndex * measureWidth +
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
    final bottomLine = clef == ClefType.treble ? 30 : 18;
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
    final rawMeasureIndex = ((x - left) / measureWidth).floor();
    final measureIndex = rawMeasureIndex
        .clamp(0, math.max(0, composition.measures.length - 1))
        .toInt();
    final capacity = composition.measureCapacityTicks(measureIndex);
    final start = contentStart(composition, measureIndex);
    final usable = measureWidth - start - 14;
    final localX = x - left - measureIndex * measureWidth - start;
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
    final usable = measureWidth - start - 14;
    return left +
        measureIndex * measureWidth +
        start +
        usable * localTick / capacity;
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
}

class ScoreView extends StatelessWidget {
  const ScoreView({
    super.key,
    required this.composition,
    this.scrollController,
    this.selectedEventIndex,
    this.playbackPosition = Duration.zero,
    this.showPlaybackCursor = false,
    this.practiceTargetTick,
    this.practiceProgress,
    this.onCursorMoved,
  });

  final Composition composition;
  final ScrollController? scrollController;
  final int? selectedEventIndex;
  final Duration playbackPosition;
  final bool showPlaybackCursor;
  final int? practiceTargetTick;
  final ValueListenable<double>? practiceProgress;
  final ValueChanged<Duration>? onCursorMoved;

  @override
  Widget build(BuildContext context) {
    final displayedMeasures = math.max(3, composition.measures.length);
    final width =
        ScoreLayout.left + displayedMeasures * ScoreLayout.measureWidth;
    return Scrollbar(
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
            height: 250,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: ScorePainter(
                    composition,
                    selectedEventIndex: selectedEventIndex,
                    playbackPosition: playbackPosition,
                    showPlaybackCursor: showPlaybackCursor,
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
    );
  }

  void _handleTap(Offset position) {
    final ticks = ScoreLayout.tickAtX(composition, position.dx);
    onCursorMoved?.call(ScoreLayout.durationAt(ticks, composition.tempoBpm));
  }
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
    this.playbackPosition = Duration.zero,
    this.showPlaybackCursor = false,
  });
  final Composition composition;
  final int? selectedEventIndex;
  final Duration playbackPosition;
  final bool showPlaybackCursor;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xff242722)
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke;
    final displayedMeasures = math.max(3, composition.measures.length);
    final staffEnd =
        ScoreLayout.left + displayedMeasures * ScoreLayout.measureWidth;

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
      final x = ScoreLayout.left + measure * ScoreLayout.measureWidth;
      canvas.drawLine(
        Offset(x, ScoreLayout.staffTop),
        Offset(x, ScoreLayout.staffTop + 4 * ScoreLayout.lineGap),
        ink..strokeWidth = measure == displayedMeasures ? 3 : 1.2,
      );
    }

    _drawText(
      canvas,
      composition.clef == ClefType.treble ? '𝄞' : '𝄢',
      const Offset(28, 75),
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
            Offset(
              ScoreLayout.left + measure.index * ScoreLayout.measureWidth + 7,
              93,
            ),
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
        Offset(
          ScoreLayout.left + measure.index * ScoreLayout.measureWidth + 6,
          174,
        ),
        11,
        color: const Color(0xff777a74),
      );
    }
    if (showPlaybackCursor) _drawPlaybackCursor(canvas);
  }

  Set<int> _selectedSourceEvents() {
    final selected = selectedEventIndex;
    if (selected == null) return const {};
    final notes = composition.measures
        .expand((measure) => measure.notes)
        .toList();
    final selectedNoteIndex = notes.indexWhere(
      (note) => note.sourceEventIndex == selected,
    );
    if (selectedNoteIndex < 0) return {selected};
    var start = selectedNoteIndex;
    while (start > 0 &&
        notes[start - 1].tieToNext &&
        notes[start].tieFromPrevious) {
      start--;
    }
    var end = selectedNoteIndex;
    while (end + 1 < notes.length &&
        notes[end].tieToNext &&
        notes[end + 1].tieFromPrevious) {
      end++;
    }
    return {
      for (var index = start; index <= end; index++)
        notes[index].sourceEventIndex,
    };
  }

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
    final step = ScoreLayout.staffStep(
      composition.clef,
      note.midiPitch,
      accidental: note.accidental,
      flatSpelling: note.flatSpelling,
    );

    if (selectedSources.contains(note.sourceEventIndex)) {
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
    if (note.tieToNext) {
      final tie = Path()
        ..moveTo(x - 2, y + 12)
        ..quadraticBezierTo(x + 14, y + 22, x + 28, y + 10);
      canvas.drawPath(tie, ink..style = PaintingStyle.stroke);
    }
  }

  void _drawKeySignature(Canvas canvas) {
    final count = composition.keySignature.accidentalCount;
    if (count == 0) return;
    const trebleSharps = [8, 5, 9, 6, 3, 7, 4];
    const bassSharps = [6, 3, 7, 4, 1, 5, 2];
    const trebleFlats = [4, 7, 3, 6, 2, 5, 1];
    const bassFlats = [2, 5, 1, 4, 0, 3, -1];
    final sharps = count > 0;
    final steps = switch ((composition.clef, sharps)) {
      (ClefType.treble, true) => trebleSharps,
      (ClefType.bass, true) => bassSharps,
      (ClefType.treble, false) => trebleFlats,
      (ClefType.bass, false) => bassFlats,
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
    final x = ScoreLayout.cursorX(composition, ticks);
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
      oldDelegate.playbackPosition != playbackPosition ||
      oldDelegate.showPlaybackCursor != showPlaybackCursor;
}
