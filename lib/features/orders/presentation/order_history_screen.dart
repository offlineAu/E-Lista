import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/order.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';

/// The signed-in shopper's orders, newest first.
///
/// Guests get this too — their orders belong to their anonymous uid — which is what makes
/// "track my order" work before anyone has created an account. The screen invites them to
/// register so the history survives losing the device, without blocking anything.
final customerOrdersProvider = StreamProvider<List<StoreOrder>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(orderRepositoryProvider).watchForCustomer(uid);
});

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(customerOrdersProvider);
    final isGuest = ref.watch(isGuestProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your orders')),
      body: AsyncView<List<StoreOrder>>(
        value: orders,
        onRetry: () => ref.invalidate(customerOrdersProvider),
        builder: (context, list) {
          if (list.isEmpty) {
            return EmptyView(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message:
                  'When you place an order it will appear here, '
                  'with its status as the store packs it.',
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Start shopping'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length + (isGuest ? 1 : 0),
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (isGuest && index == 0) return const _KeepHistoryPrompt();
              final order = list[index - (isGuest ? 1 : 0)];
              return OrderSummaryCard(
                order: order,
                onTap: () => context.go(AppRoutes.orderDetailsFor(order.id)),
              );
            },
          );
        },
      ),
    );
  }
}

class _KeepHistoryPrompt extends StatelessWidget {
  const _KeepHistoryPrompt();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.bookmark_added_outlined,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Create an account to keep your order history on any device.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () =>
                  context.push('${AppRoutes.register}?reason=order'),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One order in a list: what it cost, when, and where it is up to.
class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({
    required this.order,
    required this.onTap,
    super.key,
    this.showCustomer = false,
  });

  final StoreOrder order;
  final VoidCallback onTap;

  /// Owner lists want the customer's name; a shopper already knows who they are.
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placedAt = order.createdAt;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.orderNumber ?? 'Order ${order.id.substring(0, 6)}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  OrderStatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (showCustomer) order.contact.name,
                  '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                  order.paymentMethod.label,
                  if (placedAt != null) formatOrderDate(placedAt),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.items.map((item) => item.productName).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    order.total.format(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An order's status as a chip — icon, word and colour, never colour alone.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({
    required this.status,
    super.key,
    this.compact = false,
  });

  final OrderStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (background, foreground, icon) = switch (status) {
      OrderStatus.pending => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.schedule,
      ),
      OrderStatus.confirmed => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      OrderStatus.preparing => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.inventory_2_outlined,
      ),
      OrderStatus.ready => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.shopping_bag_outlined,
      ),
      OrderStatus.completed => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.done_all,
      ),
      OrderStatus.cancelled => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.cancel_outlined,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
            Text(
              status.label,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Today, 3:04 PM" for something recent, "9 Aug 2026" for anything older.
///
/// A shopper checking an order placed twenty minutes ago wants the time; one looking at
/// last month's wants the date.
String formatOrderDate(DateTime moment) {
  final local = moment.toLocal();
  final now = DateTime.now();
  final isToday =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;

  if (isToday) return 'Today, ${DateFormat.jm().format(local)}';

  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day;
  if (isYesterday) return 'Yesterday, ${DateFormat.jm().format(local)}';

  return DateFormat('d MMM y').format(local);
}
