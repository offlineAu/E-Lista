import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A translucent, frosted surface — the one shared implementation of the "glass" look, so
/// every screen gets the same blur radius, tint and border rather than each hand-rolling
/// its own `BackdropFilter`.
///
/// **Use sparingly.** `BackdropFilter` forces a separate compositing layer per instance and
/// is genuinely expensive on budget Android hardware — the phones this app actually runs on
/// behind a sari-sari store counter. Reserve this for the handful of surfaces the design
/// calls for (a header, one summary card, a few key cards per screen), never as a blanket
/// replacement for [Card] everywhere. Most surfaces should stay a plain `Card`.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.blur = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  /// Blur sigma. Lower than the design concept's 18-20px CSS blur reads about the same on
  /// device — Flutter's `ImageFilter.blur` sigma isn't a 1:1 unit match to CSS `blur()`.
  final double blur;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(AppTheme.radius);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: isDark ? 0.32 : 0.55,
            ),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.7),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
