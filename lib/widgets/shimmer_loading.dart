import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A shimmering placeholder block: a soft pink gradient sweeping across a rounded rect.
///
/// Used for a screen's first load — the content's shape is already visible, so nothing
/// jumps into place once the real data arrives.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({super.key, this.width, this.height, this.borderRadius = 8});

  final double? width;
  final double? height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.darkOutline : AppColors.outline;
    final highlight = isDark
        ? AppColors.darkSurfaceMuted
        : const Color(0xFFFBE7F3);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-2 + t * 4, 0),
              end: Alignment(-1 + t * 4, 0),
              colors: [base, highlight, base],
              stops: const [0.3, 0.5, 0.7],
            ),
          ),
        );
      },
    );
  }
}

/// A card-shaped skeleton row — a leading square plus two text-line bars — repeated for a
/// list's first load (products, orders, best sellers).
class ShimmerListSkeleton extends StatelessWidget {
  const ShimmerListSkeleton({
    super.key,
    this.itemCount = 5,
    this.shrinkWrap = false,
    this.padding,
  });

  final int itemCount;

  /// Set when this sits inside another scrollable (e.g. an outer `ListView`), so it sizes
  /// to its content instead of trying to scroll itself.
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: itemCount,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => const _ShimmerRowTile(),
    );
  }
}

class _ShimmerRowTile extends StatelessWidget {
  const _ShimmerRowTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const ShimmerBox(width: 52, height: 52, borderRadius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ShimmerBox(height: 13, borderRadius: 6),
                const SizedBox(height: 8),
                const SizedBox(
                  width: 120,
                  child: ShimmerBox(height: 11, borderRadius: 6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A grid of card-shaped skeletons — an image block over two text lines — for a catalog's
/// first load.
class ShimmerProductGrid extends StatelessWidget {
  const ShimmerProductGrid({super.key, required this.columns, this.itemCount = 8});

  final int columns;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ShimmerBox(borderRadius: 12)),
            SizedBox(height: 10),
            ShimmerBox(height: 13, borderRadius: 6),
            SizedBox(height: 6),
            SizedBox(width: 60, child: ShimmerBox(height: 11, borderRadius: 6)),
          ],
        ),
      ),
    );
  }
}
