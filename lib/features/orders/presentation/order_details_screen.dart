import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/order.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import 'order_history_screen.dart';

/// One order, streamed so the status updates while the customer is watching it.
final orderProvider = StreamProvider.autoDispose.family<StoreOrder?, String>((
  ref,
  orderId,
) {
  return ref.watch(orderRepositoryProvider).watch(orderId);
});

/// The order tracking and receipt screen.
///
/// [isConfirmation] switches it into the just-placed variant: a success header and, for a
/// guest, an invitation to create an account so this order survives losing the phone.
class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({
    required this.orderId,
    super.key,
    this.isConfirmation = false,
  });

  final String orderId;
  final bool isConfirmation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));

    return Scaffold(
      appBar: AppBar(
        title: Text(isConfirmation ? 'Order placed' : 'Your order'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.orders),
          icon: Icon(isConfirmation ? Icons.close : Icons.arrow_back),
          tooltip: isConfirmation ? 'Done' : 'Back',
        ),
      ),
      body: AsyncView<StoreOrder?>(
        value: order,
        onRetry: () => ref.invalidate(orderProvider(orderId)),
        builder: (context, value) {
          if (value == null) {
            return EmptyView(
              icon: Icons.receipt_long_outlined,
              title: 'Order not found',
              message: 'We could not find that order.',
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.orders),
                child: const Text('Your orders'),
              ),
            );
          }
          return _OrderBody(order: value, isConfirmation: isConfirmation);
        },
      ),
    );
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order, required this.isConfirmation});

  final StoreOrder order;
  final bool isConfirmation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isGuest = ref.watch(isGuestProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (isConfirmation) _PlacedHeader(order: order, theme: theme),
        if (isConfirmation) const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.orderNumber ?? 'Order ${order.id.substring(0, 6)}',
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
        _StatusTracker(status: order.status),
        const SizedBox(height: 24),
        if (isGuest && isConfirmation) ...[
          _KeepOrderPrompt(theme: theme),
          const SizedBox(height: 24),
        ],
        Text('Items', style: theme.textTheme.titleSmall),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                '${item.quantity} × '
                                '${item.selectedUnitPrice.format()} per ${item.unit}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
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
                  label: 'Paid by ${order.paymentMethod.label}',
                  amount: order.total,
                  emphasised: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'These are the prices at the time you ordered. They do not change if '
          'the store re-prices a product later.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text('Delivery details', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  icon: Icons.person_outline,
                  text: order.contact.name,
                ),
                _DetailRow(
                  icon: Icons.phone_outlined,
                  text: order.contact.phoneNumber,
                ),
                _DetailRow(
                  icon: order.contact.isDelivery
                      ? Icons.home_outlined
                      : Icons.storefront_outlined,
                  text: order.contact.isDelivery
                      ? order.contact.address!
                      : 'Pick up at the store',
                ),
                if (order.contact.notes != null)
                  _DetailRow(
                    icon: Icons.sticky_note_2_outlined,
                    text: order.contact.notes!,
                  ),
              ],
            ),
          ),
        ),
        if (order.status == OrderStatus.cancelled &&
            order.cancellationReason != null) ...[
          const SizedBox(height: 20),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Cancelled: ${order.cancellationReason}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => context.go(AppRoutes.home),
          child: const Text('Continue shopping'),
        ),
      ],
    );
  }
}

class _PlacedHeader extends StatelessWidget {
  const _PlacedHeader({required this.order, required this.theme});

  final StoreOrder order;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.check_circle,
              size: 44,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 12),
            Text(
              'Order placed',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The store has your order and will confirm it shortly. '
              'Show ${order.orderNumber ?? 'this screen'} at the counter.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The five steps of an order, with the current one marked.
class _StatusTracker extends StatelessWidget {
  const _StatusTracker({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (status == OrderStatus.cancelled) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.cancel_outlined,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final steps = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.completed,
    ];
    final currentStep = status.trackingStep ?? 0;

    return Semantics(
      label: 'Order status: ${status.label}. ${status.description}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var index = 0; index < steps.length; index++) ...[
                _StepDot(
                  isDone: index <= currentStep,
                  isCurrent: index == currentStep,
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 3,
                      color: index < currentStep
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(status.label, style: theme.textTheme.titleSmall),
          Text(
            status.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.isDone, required this.isCurrent});

  final bool isDone;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = isCurrent ? 22.0 : 16.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone ? theme.colorScheme.primary : theme.colorScheme.surface,
        border: Border.all(
          color: isDone
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: 2,
        ),
      ),
      child: isDone
          ? Icon(
              Icons.check,
              size: size - 8,
              color: theme.colorScheme.onPrimary,
            )
          : null,
    );
  }
}

class _KeepOrderPrompt extends StatelessWidget {
  const _KeepOrderPrompt({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create an account to keep your order history',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This order stays on this phone unless you have an account. '
              'Creating one keeps it — nothing is lost and nothing starts over.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  context.push('${AppRoutes.register}?reason=order'),
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
