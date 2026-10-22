import 'package:flutter/material.dart';

const _restInk = Color(0xff242722);

/// Draws a musical rest without relying on a device music-symbol font.
void drawRestSymbol(
  Canvas canvas,
  Offset center,
  int baseTicks, {
  double size = 24,
  Color color = _restInk,
}) {
  final scale = size / 24;
  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.1
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(scale);

  switch (baseTicks) {
    case 1920:
      // Whole rest: a block hanging from a staff line.
      canvas.drawLine(const Offset(-9, -4), const Offset(9, -4), stroke);
      canvas.drawRect(const Rect.fromLTWH(-7, -4, 14, 5.5), fill);
    case 960:
      // Half rest: a block sitting on a staff line.
      canvas.drawLine(const Offset(-9, 3), const Offset(9, 3), stroke);
      canvas.drawRect(const Rect.fromLTWH(-7, -2.5, 14, 5.5), fill);
    case 480:
      // Quarter rest: the familiar lightning shape with a lower hook.
      final path = Path()
        ..moveTo(1, -12)
        ..lineTo(5, -7)
        ..lineTo(0, -1)
        ..lineTo(5, 4)
        ..lineTo(1, 8)
        ..quadraticBezierTo(-2, 5, -5, 5)
        ..quadraticBezierTo(-1, 8, 1, 13)
        ..quadraticBezierTo(0, 9, -3, 7)
        ..lineTo(1, 3)
        ..lineTo(-4, -2)
        ..close();
      canvas.drawPath(path, fill);
    case 240:
      _drawFlaggedRest(canvas, fill, stroke, flags: 1);
    default:
      _drawFlaggedRest(canvas, fill, stroke, flags: 2);
  }

  canvas.restore();
}

void _drawFlaggedRest(
  Canvas canvas,
  Paint fill,
  Paint stroke, {
  required int flags,
}) {
  canvas.drawLine(const Offset(4, -10), const Offset(-2, 12), stroke);
  for (var flag = 0; flag < flags; flag++) {
    final y = -8.0 + flag * 7;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(1, y), width: 7, height: 5.5),
      fill,
    );
    final hook = Path()
      ..moveTo(3, y)
      ..quadraticBezierTo(8, y + 3, 4, y + 8);
    canvas.drawPath(hook, stroke);
  }
}

class RestSymbolIcon extends StatelessWidget {
  const RestSymbolIcon({
    super.key,
    this.baseTicks = 480,
    this.size = 24,
    this.color,
  });

  final int baseTicks;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? _restInk;
    return Semantics(
      label: 'Rest',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _RestSymbolPainter(baseTicks, effectiveColor),
      ),
    );
  }
}

class _RestSymbolPainter extends CustomPainter {
  const _RestSymbolPainter(this.baseTicks, this.color);

  final int baseTicks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    drawRestSymbol(
      canvas,
      size.center(Offset.zero),
      baseTicks,
      size: size.shortestSide,
      color: color,
    );
  }

  @override
  bool shouldRepaint(_RestSymbolPainter oldDelegate) =>
      baseTicks != oldDelegate.baseTicks || color != oldDelegate.color;
}
