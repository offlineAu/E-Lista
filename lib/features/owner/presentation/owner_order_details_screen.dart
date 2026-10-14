import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../models/order.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../../../widgets/text_prompt_dialog.dart';
import '../../auth/application/auth_controller.dart';
import '../../orders/presentation/order_details_screen.dart' show orderProvider;
import '../../orders/presentation/order_history_screen.dart';

/// The order's cost snapshot, which only the owner can read.
final orderCostSnapshotProvider = FutureProvider.autoDispose
    .family<OrderCostSnapshot?, String>(
      (ref, orderId) =>
          ref.watch(orderRepositoryProvider).fetchCostSnapshot(orderId),
    );

/// One order, from the store's side: what to pack, what it earns, and what to do next.
///
/// The profit figures here come from the order's frozen cost snapshot, not from what the
/// products cost today. An order packed in June shows June's margin however many times the
/// supplier has changed their price since.
class OwnerOrderDetailsScreen extends ConsumerStatefulWidget {
  const OwnerOrderDetailsScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<OwnerOrderDetailsScreen> createState() =>
      _OwnerOrderDetailsScreenState();
}

class _OwnerOrderDetailsScreenState
    extends ConsumerState<OwnerOrderDetailsScreen> {
  bool _isUpdating = false;

  Future<void> _moveTo(StoreOrder order, OrderStatus next) async {
    String? note;

    if (next == OrderStatus.cancelled) {
      note = await _askForCancellationReason();
      if (note == null) return;
    }

    setState(() => _isUpdating = true);
    try {
      await ref
          .read(storeFunctionsProvider)
          .updateOrderStatus(orderId: order.id, status: next, note: note);
      if (!mounted) return;
      showSuccessSnackBar(context, switch (next) {
        OrderStatus.cancelled => 'Order cancelled and stock returned.',
        OrderStatus.completed => 'Order completed and recorded in sales.',
        _ => 'Order marked ${next.label.toLowerCase()}.',
      });
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<String?> _askForCancellationReason() {
    return showTextPrompt(
      context,
      title: 'Cancel this order?',
      label: 'Reason',
      description:
          'The reserved stock goes back on the shelf and the customer sees '
          'why it was cancelled.',
      confirmLabel: 'Cancel order',
      cancelLabel: 'Keep the order',
    ).then((reason) {
      if (reason == null) return null;
      return reason.trim().isEmpty ? 'Cancelled by the store' : reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerOrders),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: AsyncView<StoreOrder?>(
        value: order,
        onRetry: () => ref.invalidate(orderProvider(widget.orderId)),
        builder: (context, value) {
          if (value == null) {
            return const EmptyView(
              icon: Icons.receipt_long_outlined,
              title: 'Order not found',
              message: 'This order may have been removed.',
            );
          }
          return _Body(
            order: value,
            isUpdating: _isUpdating,
            onMoveTo: (next) => _moveTo(value, next),
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.order,
    required this.isUpdating,
    required this.onMoveTo,
  });

  final StoreOrder order;
  final bool isUpdating;
  final ValueChanged<OrderStatus> onMoveTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // A cashier can process this order but never sees its cost snapshot — the rules deny
    // that read outright, so the cost is not even fetched for one, rather than fetched and
    // then hidden.
    final isCashier = ref.watch(isCashierProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.orderNumber ?? order.id.substring(0, 6),
                    style: theme.textTheme.titleMedium,
                  ),
                  if (order.createdAt != null)
                    Text(
                      formatOrderDate(order.createdAt!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            OrderStatusChip(status: order.status),
          ],
        ),
        const SizedBox(height: 20),
        _NextActions(order: order, isUpdating: isUpdating, onMoveTo: onMoveTo),
        const SizedBox(height: 24),
        Text('Customer', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.contact.name, style: theme.textTheme.bodyLarge),
                if (order.contact.phoneNumber.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(order.contact.phoneNumber),
                ],
                const SizedBox(height: 4),
                Text(
                  order.isWalkIn
                      ? 'Rung up at the register'
                      : order.contact.isDelivery
                      ? 'Deliver to ${order.contact.address}'
                      : 'Pick up at the store',
                  style: theme.textTheme.bodyMedium,
                ),
                if (order.contact.notes != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Note: ${order.contact.notes}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${order.isWalkIn ? 'Walk-in' : order.customerType.label} customer · '
                  'paying by ${order.paymentMethod.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('To pack', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final item in order.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${item.quantity}×',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.productName,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          item.lineTotal.formatExact(),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                PriceRow(label: 'Subtotal', amount: order.subtotal),
                if (order.isGcash)
                  PriceRow(
                    label: 'GCash convenience fee',
                    amount: order.convenienceFee,
                    note: 'Charged once for this order',
                  ),
                const Divider(height: 20),
                PriceRow(
                  label: order.isWalkIn ? 'Total' : 'Customer pays',
                  amount: order.total,
                  emphasised: true,
                ),
                if (order.amountTendered != null)
                  PriceRow(
                    label: 'Amount tendered',
                    amount: order.amountTendered!,
                  ),
                if (order.changeDue != null)
                  PriceRow(label: 'Change', amount: order.changeDue!),
              ],
            ),
          ),
        ),
        if (!isCashier) ...[
          const SizedBox(height: 24),
          Text('What this order earns', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _ProfitCard(
            order: order,
            costs: ref.watch(orderCostSnapshotProvider(order.id)),
          ),
        ],
      ],
    );
  }
}

class _NextActions extends StatelessWidget {
  const _NextActions({
    required this.order,
    required this.isUpdating,
    required this.onMoveTo,
  });

  final StoreOrder order;
  final bool isUpdating;
  final ValueChanged<OrderStatus> onMoveTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = order.status.allowedNext;

    if (next.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                order.status == OrderStatus.completed
                    ? Icons.done_all
                    : Icons.cancel_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(order.status.description)),
            ],
          ),
        ),
      );
    }

    final forward = next.where((status) => status != OrderStatus.cancelled);
    final canCancel = next.contains(OrderStatus.cancelled);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final status in forward)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              onPressed: isUpdating ? null : () => onMoveTo(status),
              icon: Icon(_iconFor(status)),
              label: Text('Mark ${status.label.toLowerCase()}'),
            ),
          ),
        if (canCancel)
          OutlinedButton.icon(
            onPressed: isUpdating
                ? null
                : () => onMoveTo(OrderStatus.cancelled),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel order'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
          ),
        if (order.status == OrderStatus.ready)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Completing this records the sale and keeps the stock deducted.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(OrderStatus status) => switch (status) {
    OrderStatus.confirmed => Icons.check_circle_outline,
    OrderStatus.preparing => Icons.inventory_2_outlined,
    OrderStatus.ready => Icons.shopping_bag_outlined,
    OrderStatus.completed => Icons.done_all,
    OrderStatus.cancelled => Icons.cancel_outlined,
    OrderStatus.pending => Icons.schedule,
  };
}

class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.order, required this.costs});

  final StoreOrder order;
  final AsyncValue<OrderCostSnapshot?> costs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: costs.when(
          loading: () => const LoadingView(compact: true),
          error: (error, stackTrace) => Text(
            'The cost breakdown could not be loaded.',
            style: theme.textTheme.bodyMedium,
          ),
          data: (snapshot) {
            if (snapshot == null) {
              return Text(
                'No cost record was stored for this order, so its margin cannot '
                'be shown.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }

            final cost = snapshot.totalProductCost;
            final grossProfit = order.subtotal - cost;
            final estimatedNet = grossProfit + order.convenienceFee;

            return Column(
              children: [
                PriceRow(label: 'Goods sold for', amount: order.subtotal),
                PriceRow(label: 'Goods cost you', amount: cost),
                const Divider(height: 20),
                PriceRow(
                  label: 'Margin on goods',
                  amount: grossProfit,
                  amountColor: grossProfit.isNegative
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                if (order.isGcash)
                  PriceRow(
                    label: 'GCash fee collected',
                    amount: order.convenienceFee,
                  ),
                const Divider(height: 20),
                PriceRow(
                  label: 'Estimated profit',
                  amount: estimatedNet,
                  emphasised: true,
                ),
                const SizedBox(height: 8),
                Text(
                  'Estimated: it counts the convenience fee as income and does '
                  'not know what GCash charges you in return.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (cost.isZero && order.subtotal > Money.zero) ...[
                  const SizedBox(height: 8),
                  Text(
                    'No cost was recorded against these products, so the margin '
                    'above is the full sale price.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
