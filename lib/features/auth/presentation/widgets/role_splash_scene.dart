import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Which of the three animated splash scenes to show, or none while the session is still
/// resolving and the role is not known yet.
enum SplashScene { owner, cashier, customer }

/// The per-role words and colours the splash screen wraps around each [SplashScene] — the
/// role pill, the tagline, and the shimmer bar's gradient.
extension SplashSceneStyle on SplashScene {
  String get roleLabel => switch (this) {
    SplashScene.owner => 'OWNER',
    SplashScene.cashier => 'CASHIER',
    SplashScene.customer => 'CUSTOMER',
  };

  String get tagline => switch (this) {
    SplashScene.owner => 'Preparing your dashboard',
    SplashScene.cashier => 'Ready for the register',
    SplashScene.customer => 'Loading the shelves',
  };

  Color get tagForeground => switch (this) {
    SplashScene.owner => AppColors.primaryRoseDark,
    SplashScene.cashier => AppColors.onAccentVioletContainer,
    SplashScene.customer => AppColors.primaryRose,
  };

  Color get tagBackground => switch (this) {
    SplashScene.owner => AppColors.tertiaryPinkContainer,
    SplashScene.cashier => AppColors.accentVioletContainer,
    SplashScene.customer => AppColors.tertiaryPinkContainer,
  };

  List<Color> get barColors => switch (this) {
    SplashScene.owner => [
      AppColors.primaryRose,
      AppColors.tertiaryPink,
      AppColors.accentViolet,
    ],
    SplashScene.cashier => [
      AppColors.accentViolet,
      AppColors.accentVioletOnDark,
      AppColors.primaryRose,
    ],
    SplashScene.customer => [
      AppColors.tertiaryPink,
      AppColors.primaryRoseContainer,
      AppColors.primaryRose,
    ],
  };

  Color get barTrackColor => switch (this) {
    SplashScene.owner => AppColors.outline,
    SplashScene.cashier => AppColors.accentVioletContainer,
    SplashScene.customer => AppColors.tertiaryPinkContainer,
  };
}

/// A small looping illustration hinting at what this role's app is about — bars trending up
/// for the owner, a receipt printing for the cashier, items dropping into a bag for the
/// customer. Purely decorative: it says nothing the rest of the splash screen doesn't
/// already say in words, so a failure to build it would never be worth surfacing to anyone.
class RoleSplashScene extends StatefulWidget {
  const RoleSplashScene({required this.scene, super.key, this.size = 96});

  final SplashScene scene;
  final double size;

  @override
  State<RoleSplashScene> createState() => _RoleSplashSceneState();
}

class _RoleSplashSceneState extends State<RoleSplashScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = switch (widget.scene) {
      SplashScene.owner => _OwnerScenePainter(_controller),
      SplashScene.cashier => _CashierScenePainter(_controller),
      SplashScene.customer => _CustomerScenePainter(_controller),
    };

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(painter: painter),
      ),
    );
  }
}

/// Bars growing in, staggered, with a trend line sweeping across their peaks.
class _OwnerScenePainter extends CustomPainter {
  _OwnerScenePainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _heights = [0.45, 0.72, 0.58, 0.9];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final barWidth = size.width / (_heights.length * 2 - 1);
    final points = <Offset>[];

    for (var i = 0; i < _heights.length; i++) {
      // Each bar's growth is staggered a fifth of the loop behind the last.
      final localT = (((t - i * 0.12) % 1) + 1) % 1;
      final grown = Curves.easeOutCubic.transform(
        (localT < 0.6 ? localT / 0.6 : 1.0).clamp(0.0, 1.0),
      );
      final barHeight = size.height * _heights[i] * grown;
      final x = i * barWidth * 2;
      final rect = Rect.fromLTWH(
        x,
        size.height - barHeight,
        barWidth,
        barHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()
          ..color = AppColors.primaryRose.withValues(alpha: 0.55 + 0.15 * grown),
      );
      points.add(Offset(x + barWidth / 2, size.height - barHeight));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accentViolet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _OwnerScenePainter oldDelegate) => true;
}

/// A receipt unrolling from the top, printed lines appearing in step, with a coin bouncing
/// beside it.
class _CashierScenePainter extends CustomPainter {
  _CashierScenePainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final unrollT = Curves.easeOutCubic.transform(
      (t < 0.55 ? t / 0.55 : 1.0).clamp(0.0, 1.0),
    );

    final receiptWidth = size.width * 0.5;
    final receiptHeight = size.height * 0.78 * unrollT;
    final left = size.width * 0.14;
    final top = size.height * 0.1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, receiptWidth, receiptHeight),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    final linePaint = Paint()
      ..color = AppColors.primaryRoseDark.withValues(alpha: 0.4)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const lineCount = 4;
    for (var i = 0; i < lineCount; i++) {
      final lineReveal = ((unrollT - i * 0.15) * 3).clamp(0.0, 1.0);
      if (lineReveal <= 0) continue;
      final y = top + 12 + i * 10;
      if (y > top + receiptHeight - 6) continue;
      canvas.drawLine(
        Offset(left + 8, y),
        Offset(left + 8 + (receiptWidth - 16) * lineReveal, y),
        linePaint,
      );
    }

    // The coin drops and settles with a small bounce, looping.
    final coinT = ((t - 0.35).clamp(0.0, 1.0)) / 0.65;
    final bounce = coinT <= 0
        ? 0.0
        : Curves.bounceOut.transform(coinT.clamp(0.0, 1.0));
    final coinRadius = size.width * 0.09;
    final coinCenter = Offset(
      size.width * 0.82,
      size.height * 0.18 + (size.height * 0.62) * bounce,
    );
    canvas.drawCircle(
      coinCenter,
      coinRadius,
      Paint()..color = AppColors.accentViolet,
    );
    canvas.drawCircle(
      coinCenter,
      coinRadius * 0.55,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CashierScenePainter oldDelegate) => true;
}

/// Items dropping one by one into a shopping bag, each settling with a small bounce.
class _CustomerScenePainter extends CustomPainter {
  _CustomerScenePainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _dropDelays = [0.0, 0.18, 0.34];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final unit = size.width / 100;

    final bag = Path()
      ..moveTo(24 * unit, 46 * unit)
      ..lineTo(76 * unit, 46 * unit)
      ..lineTo(68 * unit, 88 * unit)
      ..lineTo(32 * unit, 88 * unit)
      ..close();
    canvas.drawPath(bag, Paint()..color = AppColors.primaryRose);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(50 * unit, 46 * unit), radius: 16 * unit),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = AppColors.primaryRoseDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * unit
        ..strokeCap = StrokeCap.round,
    );

    final itemColors = [
      AppColors.accentViolet,
      AppColors.tertiaryPink,
      AppColors.accentVioletOnDark,
    ];
    final targets = [
      Offset(38 * unit, 68 * unit),
      Offset(52 * unit, 74 * unit),
      Offset(62 * unit, 66 * unit),
    ];

    for (var i = 0; i < _dropDelays.length; i++) {
      final localT = (((t - _dropDelays[i]) % 1) + 1) % 1;
      // Falls for the first third of its cycle, then rests in the bag.
      final fallT = (localT / 0.4).clamp(0.0, 1.0);
      if (localT > 0.4) continue;
      final eased = Curves.easeIn.transform(fallT);
      final y = -10 * unit + (targets[i].dy - (-10 * unit)) * eased;
      final opacity = fallT < 0.05 ? fallT / 0.05 : 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(targets[i].dx, y),
            width: 10 * unit,
            height: 10 * unit,
          ),
          Radius.circular(2 * unit),
        ),
        Paint()..color = itemColors[i].withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CustomerScenePainter oldDelegate) => true;
}
