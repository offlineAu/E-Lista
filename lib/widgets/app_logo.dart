import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The E-Lista brand mark: a woven *bayong* basket in deep green, with a warm yellow
/// sun-burst behind it.
///
/// Drawn rather than shipped as an asset so it stays crisp at any size and takes on the
/// theme's colours in dark mode without a second file.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64, this.showBackground = true});

  final double size;

  /// The rounded background tile. Off when the mark sits inside another coloured surface.
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: size,
      height: size,
      child: Semantics(
        label: 'E-Lista',
        child: CustomPaint(
          painter: _LogoPainter(
            basket: isDark ? AppColors.greenOnDark : AppColors.deepGreen,
            accent: isDark ? AppColors.yellowOnDark : AppColors.warmYellow,
            background: showBackground
                ? (isDark
                      ? AppColors.darkSurfaceMuted
                      : AppColors.greenContainer)
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({
    required this.basket,
    required this.accent,
    required this.background,
  });

  final Color basket;
  final Color accent;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 100;
    final paint = Paint()..isAntiAlias = true;

    if (background.a > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(24 * unit)),
        paint..color = background,
      );
    }

    // Sun-burst behind the basket.
    paint.color = accent;
    const rayCount = 7;
    final centre = Offset(50 * unit, 44 * unit);
    for (var i = 0; i < rayCount; i++) {
      final angle = math.pi + (math.pi / (rayCount - 1)) * i;
      final start =
          centre + Offset(math.cos(angle), math.sin(angle)) * 20 * unit;
      final end = centre + Offset(math.cos(angle), math.sin(angle)) * 31 * unit;
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = accent
          ..strokeWidth = 4 * unit
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    // Basket body: a trapezium, narrower at the base.
    final body = Path()
      ..moveTo(26 * unit, 46 * unit)
      ..lineTo(74 * unit, 46 * unit)
      ..lineTo(66 * unit, 80 * unit)
      ..lineTo(34 * unit, 80 * unit)
      ..close();
    canvas.drawPath(body, paint..color = basket);

    // Handle.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(50 * unit, 46 * unit), radius: 17 * unit),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = basket
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * unit
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );

    // Weave: two lighter bands across the basket.
    final weave = Paint()
      ..color = accent
      ..strokeWidth = 3.5 * unit
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(
      Offset(30 * unit, 58 * unit),
      Offset(70 * unit, 58 * unit),
      weave,
    );
    canvas.drawLine(
      Offset(32 * unit, 69 * unit),
      Offset(68 * unit, 69 * unit),
      weave,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) =>
      oldDelegate.basket != basket ||
      oldDelegate.accent != accent ||
      oldDelegate.background != background;
}
