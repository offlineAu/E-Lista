import 'package:flutter/material.dart';

/// A minimal, axis-free line — the shape of a trend, not its exact values. No legend, no
/// labels, no tooltip: a sparkline is the one chart form that skips all three by design.
class Sparkline extends StatelessWidget {
  const Sparkline({required this.values, super.key, this.height = 32, this.color});

  final List<double> values;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final lineColor = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, color: lineColor),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (maxValue - minValue).abs() < 1e-9 ? 1.0 : maxValue - minValue;
    final stepX = size.width / (values.length - 1);

    Offset pointAt(int i) {
      final normalized = (values[i] - minValue) / range;
      return Offset(i * stepX, size.height - normalized * size.height);
    }

    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final point = pointAt(i);
      linePath.lineTo(point.dx, point.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(pointAt(values.length - 1).dx, size.height)
      ..lineTo(pointAt(0).dx, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(pointAt(values.length - 1), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
