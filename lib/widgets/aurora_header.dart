import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The animated, gradient-blob "aurora" header — a greeting, a big bold title, an optional
/// leading mark and trailing actions, over a continuously drifting mesh of blurred color
/// blobs with a soft curved bottom edge.
///
/// [chip] straddles the curve deliberately: it is positioned as a sibling of the clipped
/// header box, not inside it — putting it inside would have it silently clipped by the
/// header's own bounds, which is exactly the bug an earlier design pass caught and fixed.
class AuroraHeader extends StatefulWidget {
  const AuroraHeader({
    required this.greeting,
    required this.title,
    super.key,
    this.leading,
    this.actions = const [],
    this.chip,
    this.height = 200,
  });

  final String greeting;
  final String title;
  final Widget? leading;
  final List<Widget> actions;

  /// A small card meant to float over the header/body boundary, e.g. a headline stat.
  final Widget? chip;

  final double height;

  @override
  State<AuroraHeader> createState() => _AuroraHeaderState();
}

class _AuroraHeaderState extends State<AuroraHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Room below the header for a chip straddling the curve, same allowance the concept
    // canvas used (the chip's own height minus how far it tucks into the header).
    final extraBottomSpace = widget.chip == null ? 0.0 : 30.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipPath(
          clipper: const _HeaderCurveClipper(),
          child: SizedBox(
            height: widget.height,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFF2A1030)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) =>
                        CustomPaint(painter: _AuroraPainter(_controller.value)),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.greeting,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                              ),
                              if (widget.leading != null) widget.leading!,
                              for (final action in widget.actions) action,
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.chip != null)
          Positioned(
            right: 20,
            top: widget.height - extraBottomSpace,
            child: widget.chip!,
          ),
        SizedBox(height: widget.height + extraBottomSpace),
      ],
    );
  }
}

/// A gentle wave along the bottom edge, matching the concept canvas's curve.
class _HeaderCurveClipper extends CustomClipper<Path> {
  const _HeaderCurveClipper();

  @override
  Path getClip(Size size) {
    final h = size.height;
    final w = size.width;
    return Path()
      ..lineTo(0, h - h * 0.11)
      ..quadraticBezierTo(w * 0.32, h, w * 0.55, h - h * 0.06)
      ..quadraticBezierTo(w * 0.75, h - h * 0.12, w, h - h * 0.02)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Four soft, drifting blobs — cheap on purpose: each is blurred via `Paint.imageFilter` into
/// its own small offscreen layer, unlike [BackdropFilter], which would force a full
/// compositing layer of everything behind it. A header that repaints every frame is not the
/// place for that cost.
class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);

  /// 0..1, looping.
  final double t;

  static const _blobs = [
    (AppColors.tertiaryPink, 0.85, 0.28, -0.22, 0.0),
    (AppColors.accentViolet, 0.8, 0.22, 0.86, 0.22),
    (AppColors.primaryRoseDark, 0.75, 0.20, 0.62, 0.55),
    (AppColors.accentVioletOnDark, 0.55, 0.16, 0.94, 0.78),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (color, opacity, radiusFactor, phase, speedOffset) in _blobs) {
      final angle = (t + speedOffset) * 2 * math.pi;
      final dx = math.cos(angle) * 0.06;
      final dy = math.sin(angle) * 0.05;
      final center = Offset(
        (phase + dx) * size.width,
        (0.25 + dy) * size.height,
      );
      final radius = radiusFactor * size.shortestSide * 1.4;

      canvas.saveLayer(
        Rect.fromCircle(center: center, radius: radius * 1.6),
        Paint(),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..imageFilter = ImageFilter.blur(sigmaX: 34, sigmaY: 34),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.t != t;
}
