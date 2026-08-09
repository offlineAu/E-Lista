import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/inventory_transaction.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/state_views.dart';
import '../../orders/presentation/order_history_screen.dart'
    show formatOrderDate;
import '../application/dashboard_providers.dart';

/// The stock ledger: every movement, newest first.
///
/// Each row carries the balance before and after, not just the change, so the owner can
/// see at a glance that the ledger adds up without replaying it from the beginning.
class InventoryHistoryScreen extends ConsumerWidget {
  const InventoryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(recentInventoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory history'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerInventory),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: AsyncView<List<InventoryTransaction>>(
        value: transactions,
        onRetry: () => ref.invalidate(recentInventoryProvider),
        builder: (context, list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.history,
              title: 'No stock movements yet',
              message: 'Restocks, sales and corrections all appear here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                InventoryTransactionTile(transaction: list[index]),
          );
        },
      ),
    );
  }
}

/// One ledger row.
class InventoryTransactionTile extends StatelessWidget {
  const InventoryTransactionTile({required this.transaction, super.key});

  final InventoryTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncrease = transaction.isIncrease;
    final colour = isIncrease
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(transaction.type), color: colour, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      transaction.type.label,
                      '${transaction.previousStock} → ${transaction.newStock}',
                      if (transaction.createdAt != null)
                        formatOrderDate(transaction.createdAt!),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (transaction.reason != null) ...[
                    const SizedBox(height: 4),
                    Text(transaction.reason!, style: theme.textTheme.bodySmall),
                  ],
                  if (transaction.unitCost != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Cost ${transaction.unitCost!.format()} each',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (!transaction.isConsistent) ...[
                    const SizedBox(height: 4),
                    Text(
                      'This row does not add up and may have been written by an '
                      'older version of the app.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              transaction.signedQuantityLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colour,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(InventoryTransactionType type) => switch (type) {
    InventoryTransactionType.restock => Icons.add_box_outlined,
    InventoryTransactionType.sale => Icons.shopping_cart_outlined,
    InventoryTransactionType.adjustment => Icons.tune,
    InventoryTransactionType.damage => Icons.broken_image_outlined,
    InventoryTransactionType.expired => Icons.event_busy_outlined,
    InventoryTransactionType.returned => Icons.undo,
  };
}
