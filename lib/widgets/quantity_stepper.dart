import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A minus / number / plus control for choosing how many.
///
/// Both buttons are full 48dp targets, because this is tapped repeatedly by someone
/// holding a phone in one hand. The control clamps to [maximum] rather than letting the
/// number climb past what is in stock and failing at checkout instead.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    required this.quantity,
    required this.onChanged,
    super.key,
    this.minimum = 1,
    this.maximum,
    this.enabled = true,
    this.compact = false,
    this.semanticLabel,
  });

  final int quantity;
  final ValueChanged<int> onChanged;

  /// Below this, the caller decides what happens — the cart removes the line at zero.
  final int minimum;

  /// Usually the stock on hand. `null` for unbounded.
  final int? maximum;

  final bool enabled;
  final bool compact;

  /// What the whole control announces, e.g. the product name.
  final String? semanticLabel;

  bool get _canDecrease => enabled && quantity > minimum;
  bool get _canIncrease => enabled && (maximum == null || quantity < maximum!);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = compact ? 40.0 : AppTheme.minTouchTarget;

    return Semantics(
      label: semanticLabel == null ? 'Quantity' : 'Quantity of $semanticLabel',
      value: '$quantity',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              icon: Icons.remove,
              tooltip: 'Decrease quantity',
              size: size,
              onPressed: _canDecrease ? () => onChanged(quantity - 1) : null,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: compact ? 32 : 44),
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style:
                    (compact
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              tooltip: _canIncrease
                  ? 'Increase quantity'
                  : 'No more stock available',
              size: size,
              onPressed: _canIncrease ? () => onChanged(quantity + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
