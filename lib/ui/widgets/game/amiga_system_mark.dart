import 'package:flutter/material.dart';

/// Geometric stand-in for the Commodore Amiga on system lists. Not the
/// trademark boing ball: a check, which is the shape people already associate
/// with the machine, drawn so it stays legible at the tile's icon size.
class AmigaSystemMark extends StatelessWidget {
  const AmigaSystemMark({super.key, this.size = 28, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AmigaMarkPainter(color),
    );
  }
}

class _AmigaMarkPainter extends CustomPainter {
  const _AmigaMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s * 0.18, s * 0.52)
      ..lineTo(s * 0.40, s * 0.74)
      ..lineTo(s * 0.82, s * 0.26);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AmigaMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
