import 'package:flutter/material.dart';

import '../models/measure_marks.dart';

class MeasureMarkIcon extends StatelessWidget {
  const MeasureMarkIcon({
    super.key,
    required this.edge,
    required this.color,
    this.volta = false,
    this.number,
  });

  final MeasureEdge edge;
  final Color color;
  final bool volta;
  final String? number;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(32, 26),
    painter: _MarkPainter(edge, color, volta, number),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.edge, this.color, this.volta, this.number);
  final MeasureEdge edge;
  final Color color;
  final bool volta;
  final String? number;

  @override
  void paint(Canvas canvas, Size size) {
    final left = edge == MeasureEdge.left;
    final paint = Paint()..color = color;
    if (volta) {
      final x = left ? 3.0 : size.width - 3;
      paint.strokeWidth = 1.8;
      canvas.drawLine(Offset(3, 3), Offset(size.width - 3, 3), paint);
      canvas.drawLine(Offset(x, 3), Offset(x, 13), paint);
      final text = TextPainter(
        text: TextSpan(
          text: number ?? '–',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width - 8);
      text.paint(canvas, Offset(left ? 7 : size.width - 7 - text.width, 7));
    } else {
      final x = left ? 9.0 : size.width - 9;
      paint.strokeWidth = 3;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), paint);
      final thin = x + (left ? 5 : -5);
      paint.strokeWidth = 1.2;
      canvas.drawLine(Offset(thin, 2), Offset(thin, size.height - 2), paint);
      final dots = x + (left ? 11 : -11);
      canvas.drawCircle(Offset(dots, 9), 2, paint);
      canvas.drawCircle(Offset(dots, 17), 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      edge != oldDelegate.edge ||
      color != oldDelegate.color ||
      volta != oldDelegate.volta ||
      number != oldDelegate.number;
}
