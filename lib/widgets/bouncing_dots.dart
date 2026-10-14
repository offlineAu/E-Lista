import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Three dots bouncing in a staggered wave — a short inline wait (checking stock, applying
/// a filter), too brief to warrant a full skeleton and too active for a plain spinner.
class BouncingDots extends StatefulWidget {
  const BouncingDots({super.key, this.size = 9});

  final double size;

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  static const _colors = [
    AppColors.primaryRose,
    AppColors.tertiaryPink,
    AppColors.primaryRoseContainer,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.15;
            final t = ((_controller.value - delay) % 1.0 + 1.0) % 1.0;
            final bounce = t >= 0.8
                ? 0.0
                : (t / 0.8 < 0.5 ? (t / 0.8) * 2 : 2 - (t / 0.8) * 2);
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
              child: Transform.translate(
                offset: Offset(0, -8 * bounce),
                child: Opacity(
                  opacity: 0.5 + 0.5 * bounce,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: _colors[i],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// A [BouncingDots] paired with a short label, matching the concept's "Checking stock…"
/// inline-wait treatment.
class InlineWaitRow extends StatelessWidget {
  const InlineWaitRow({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BouncingDots(),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
