import 'package:flutter/material.dart';
import 'dart:ui' show PointMode;

class DotGridBackground extends StatelessWidget {
  final Widget? child;
  final Color backgroundColor;
  final Color dotColor;
  final double spacing;
  final double dotRadius;

  const DotGridBackground({
    super.key,
    this.child,
    this.backgroundColor = const Color(0xFFF1F2F4),
    this.dotColor = const Color.fromRGBO(26, 42, 59, 0.16),
    this.spacing = 28,
    this.dotRadius = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: CustomPaint(
        painter: _DotGridPainter(dotColor, spacing, dotRadius),
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color dotColor;
  final double spacing;
  final double dotRadius;
  _DotGridPainter(this.dotColor, this.spacing, this.dotRadius);

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[];
    for (double y = 0; y <= size.height; y += spacing) {
      for (double x = 0; x <= size.width; x += spacing) {
        points.add(Offset(x, y));
      }
    }
    final paint = Paint()
      ..color = dotColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = dotRadius * 2
      ..isAntiAlias = true;
    canvas.drawPoints(PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) =>
      old.dotColor != dotColor || old.spacing != spacing || old.dotRadius != dotRadius;
}
