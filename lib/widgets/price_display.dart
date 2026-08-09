import 'package:flutter/material.dart';

import '../core/money/money.dart';
import '../core/theme/app_colors.dart';
import '../models/payment_method.dart';

/// Shows the two prices a product has, side by side.
///
/// Cash and GCash prices differ on purpose — cash is a whole-peso markup, GCash is a true
/// margin — so showing only one would leave a shopper surprised at checkout. They are
/// labelled rather than distinguished by colour alone, so the difference survives
/// greyscale, glare and colour blindness.
class DualPriceView extends StatelessWidget {
  const DualPriceView({
    required this.cashPrice,
    required this.gcashPrice,
    super.key,
    this.compact = false,
    this.highlight,
  });

  final Money cashPrice;
  final Money gcashPrice;

  /// Tighter layout for product cards in a grid.
  final bool compact;

  /// Emphasises the price for the method the customer has chosen.
  final PaymentMethod? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PriceColumn(
            label: PaymentMethod.cash.label,
            amount: cashPrice,
            compact: compact,
            emphasised: highlight == PaymentMethod.cash,
          ),
        ),
        SizedBox(width: compact ? 8 : 16),
        Expanded(
          child: _PriceColumn(
            label: PaymentMethod.gcash.label,
            amount: gcashPrice,
            compact: compact,
            emphasised: highlight == PaymentMethod.gcash,
            accent: theme.colorScheme.tertiary,
          ),
        ),
      ],
    );
  }
}

class _PriceColumn extends StatelessWidget {
  const _PriceColumn({
    required this.label,
    required this.amount,
    required this.compact,
    required this.emphasised,
    this.accent,
  });

  final String label;
  final Money amount;
  final bool compact;
  final bool emphasised;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = accent ?? theme.colorScheme.primary;

    return Semantics(
      label: '$label price ${amount.format()}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style:
                (compact
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.labelMedium)
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            amount.format(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (compact
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.headlineSmall)
                    ?.copyWith(
                      color: colour,
                      fontWeight: emphasised
                          ? FontWeight.w800
                          : FontWeight.w700,
                    ),
          ),
        ],
      ),
    );
  }
}

/// A single price with a label, for totals and line items.
class PriceRow extends StatelessWidget {
  const PriceRow({
    required this.label,
    required this.amount,
    super.key,
    this.emphasised = false,
    this.note,
    this.amountColor,
  });

  final String label;
  final Money amount;

  /// Larger and bolder — for the line the customer actually pays.
  final bool emphasised;

  /// A clarifying line under the label, e.g. which fee tier applied.
  final String? note;

  final Color? amountColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = emphasised
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    final amountStyle = emphasised
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            // Totals align better with centavos always shown; the emphasised final line
            // reads more naturally without a trailing ".00".
            emphasised ? amount.format() : amount.formatExact(),
            style: amountStyle?.copyWith(color: amountColor),
          ),
        ],
      ),
    );
  }
}

/// The stock state of a product, as a badge.
///
/// Never colour alone: each state has its own icon and words, so "low stock" is legible to
/// someone who cannot tell the amber from the green.
class StockBadge extends StatelessWidget {
  const StockBadge({
    required this.stockQuantity,
    required this.lowStockThreshold,
    super.key,
    this.showQuantity = true,
  });

  final int stockQuantity;
  final int lowStockThreshold;

  /// Owner screens want the number; customer screens usually just want the state.
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (label, icon, foreground, background) = switch (stockQuantity) {
      <= 0 => (
        'Out of stock',
        Icons.remove_shopping_cart_outlined,
        isDark ? AppColors.dangerOnDark : AppColors.onDangerContainer,
        isDark ? AppColors.darkSurfaceMuted : AppColors.dangerContainer,
      ),
      _ when stockQuantity <= lowStockThreshold => (
        showQuantity ? 'Low stock · $stockQuantity left' : 'Low stock',
        Icons.warning_amber_rounded,
        isDark ? AppColors.warningOnDark : AppColors.onWarningContainer,
        isDark ? AppColors.darkSurfaceMuted : AppColors.warningContainer,
      ),
      _ => (
        showQuantity ? '$stockQuantity in stock' : 'In stock',
        Icons.check_circle_outline,
        isDark ? AppColors.successOnDark : AppColors.onSuccessContainer,
        isDark ? AppColors.darkSurfaceMuted : AppColors.successContainer,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
