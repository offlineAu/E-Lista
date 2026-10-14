import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The E-Lista brand mark: a tote bag with a live pulse line running through it — the bag
/// is "store," the pulse is "system," sales moving in real time.
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
    final brand = isDark ? AppColors.primaryRoseDark : AppColors.primaryRose;

    return SizedBox(
      width: size,
      height: size,
      child: Semantics(
        label: 'E-Lista',
        child: CustomPaint(
          painter: _LogoPainter(
            brand: brand,
            bag: AppColors.tertiaryPinkContainer,
            background: showBackground ? brand : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({
    required this.brand,
    required this.bag,
    required this.background,
  });

  final Color brand;
  final Color bag;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 96;
    final paint = Paint()..isAntiAlias = true;

    if (background.a > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(24 * unit)),
        paint..color = background,
      );
    }

    // Handle: an arc peeking above the bag, same pale tone as the bag itself.
    canvas.drawPath(
      Path()
        ..moveTo(32 * unit, 34 * unit)
        ..quadraticBezierTo(32 * unit, 20 * unit, 48 * unit, 20 * unit)
        ..quadraticBezierTo(64 * unit, 20 * unit, 64 * unit, 34 * unit),
      Paint()
        ..color = bag
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * unit
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );

    // Bag body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(22 * unit, 34 * unit, 52 * unit, 44 * unit),
        Radius.circular(12 * unit),
      ),
      paint..color = bag,
    );

    // Pulse line through the bag.
    canvas.drawPath(
      Path()
        ..moveTo(28 * unit, 56 * unit)
        ..lineTo(40 * unit, 56 * unit)
        ..lineTo(46 * unit, 46 * unit)
        ..lineTo(52 * unit, 64 * unit)
        ..lineTo(58 * unit, 52 * unit)
        ..lineTo(64 * unit, 56 * unit)
        ..lineTo(70 * unit, 56 * unit),
      Paint()
        ..color = brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) =>
      oldDelegate.brand != brand ||
      oldDelegate.bag != bag ||
      oldDelegate.background != background;
}
