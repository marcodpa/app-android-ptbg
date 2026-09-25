import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared cartridge drawing for the module card and the navigation rail.
class FilterCartridgeIcon extends StatelessWidget {
  const FilterCartridgeIcon({super.key, required this.color, this.size = 32});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _CartridgePainter(color))));
}

class _CartridgePainter extends CustomPainter {
  const _CartridgePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double a, double b) =>
        canvas.drawLine(Offset(x, y), Offset(a, b), pen);
    canvas.drawOval(const Rect.fromLTWH(27, 10, 46, 17), pen);
    canvas.drawOval(const Rect.fromLTWH(44, 15, 12, 6), pen);
    line(27, 19, 27, 80);
    line(73, 19, 73, 80);
    canvas.drawArc(const Rect.fromLTWH(27, 71, 46, 17), 0, math.pi, false, pen);
    for (var x = 33.0; x <= 68; x += 6) {
      final bend = (1 - ((x - 50).abs() / 23)) * 5;
      line(x, 24 + bend, x, 81 + bend);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CartridgePainter oldDelegate) =>
      oldDelegate.color != color;
}
