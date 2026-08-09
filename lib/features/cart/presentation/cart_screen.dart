import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../features/pricing/domain/gcash_fee_schedule.dart';
import '../../../models/cart.dart';
import '../../../models/payment_method.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/quantity_stepper.dart';
import '../../../widgets/state_views.dart';
import '../application/cart_controller.dart';

/// The basket, with a running total that reacts to the chosen payment method.
///
/// The totals here are a **preview**. `placeOrder` re-reads every product and recomputes
/// the price, the fee and the total server-side, and refuses the order if what the shopper
/// was shown no longer matches. Showing the figure early is a courtesy; charging from it
/// would be a bug.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  void initState() {
    super.initState();
    // Prices and stock may have moved since the shopper added these. Refresh once on open
    // rather than letting them reach checkout with a figure from last week.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      await ref.read(cartControllerProvider).refreshFromCatalog();
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final method = ref.watch(selectedPaymentMethodProvider);
    final schedule = ref.watch(gcashFeeScheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your cart'),
        actions: [
          if (cart.valueOrNull?.isNotEmpty ?? false)
            TextButton(onPressed: _confirmClear, child: const Text('Clear')),
        ],
      ),
      body: AsyncView<Cart>(
        value: cart,
        onRetry: _refresh,
        builder: (context, value) {
          if (value.isEmpty) {
            return EmptyView(
              icon: Icons.shopping_cart_outlined,
              title: 'Your cart is empty',
              message:
                  'Add something from the shelves and it will show up here.',
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Start shopping'),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: value.items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _CartLine(item: value.items[index], method: method),
                  ),
                ),
              ),
              _CartSummary(cart: value, method: method, schedule: schedule),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear your cart?'),
        content: const Text('This removes everything you have added.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear cart'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await ref.read(cartControllerProvider).clear();
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    }
  }
}

class _CartLine extends ConsumerWidget {
  const _CartLine({required this.item, required this.method});

  final CartItem item;
  final PaymentMethod method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.watch(cartControllerProvider);
    final problem = item.problemMessage;

    Future<void> change(int quantity) async {
      try {
        await controller.setQuantity(item.productId, quantity);
      } catch (error) {
        if (!context.mounted) return;
        showFailureSnackBar(context, error);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.brand != null && item.brand!.isNotEmpty)
                        Text(
                          item.brand!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        item.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.unitPrice(method).format()} per ${item.unit}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  item.lineTotal(method).format(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (problem != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      problem,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                QuantityStepper(
                  quantity: item.quantity,
                  minimum: 1,
                  maximum: item.availableStock <= 0 ? 1 : item.availableStock,
                  compact: true,
                  semanticLabel: item.productName,
                  onChanged: change,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => change(0),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartSummary extends ConsumerWidget {
  const _CartSummary({
    required this.cart,
    required this.method,
    required this.schedule,
  });

  final Cart cart;
  final PaymentMethod method;
  final AsyncValue<GcashFeeSchedule> schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final feeSchedule = schedule.valueOrNull;
    final subtotal = cart.subtotal(method);

    final fee = (method.chargesConvenienceFee && feeSchedule != null)
        ? feeSchedule.feeFor(subtotal)
        : Money.zero;
    final total = subtotal + fee;
    final tier = (method.chargesConvenienceFee && feeSchedule != null)
        ? feeSchedule.tierFor(subtotal)
        : null;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: theme.colorScheme.shadow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PaymentMethodSelector(selected: method),
              const SizedBox(height: 12),
              PriceRow(
                label: 'Subtotal (${cart.itemCount} items)',
                amount: subtotal,
              ),
              if (method.chargesConvenienceFee)
                PriceRow(
                  label: 'GCash convenience fee',
                  amount: fee,
                  note: tier == null
                      ? 'Charged once for the whole order.'
                      : 'Charged once for the whole order · ${tier.rangeLabel}',
                ),
              const Divider(height: 20),
              PriceRow(
                label: '${method.label} total',
                amount: total,
                emphasised: true,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: cart.canCheckout && feeSchedule != null
                    ? () => context.go(AppRoutes.checkout)
                    : null,
                child: Text(
                  cart.canCheckout
                      ? 'Checkout · ${total.format()}'
                      : 'Fix the items above to continue',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cash or GCash, chosen in the cart so the running total reflects it.
class _PaymentMethodSelector extends ConsumerWidget {
  const _PaymentMethodSelector({required this.selected});

  final PaymentMethod selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<PaymentMethod>(
      segments: [
        for (final method in PaymentMethod.values)
          ButtonSegment<PaymentMethod>(
            value: method,
            label: Text(method.label),
            icon: Icon(
              method == PaymentMethod.cash
                  ? Icons.payments_outlined
                  : Icons.account_balance_wallet_outlined,
            ),
          ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        ref.read(selectedPaymentMethodProvider.notifier).state =
            selection.first;
      },
    );
  }
}
