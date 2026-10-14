import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/product_batch.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/state_views.dart';
import '../application/owner_product_providers.dart';

/// One product's batches, oldest-expiring first — the order they will actually sell in.
///
/// Unlike price history, a batch is not a pure record: [ProductBatch.remainingQuantity]
/// shrinks as FEFO sells or writes it off, so this reads as "what's left to sell," not as an
/// audit trail.
class ProductBatchesScreen extends ConsumerWidget {
  const ProductBatchesScreen({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(productBatchesProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batches'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerProductEditFor(productId)),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: AsyncView<List<ProductBatch>>(
        value: batches,
        onRetry: () => ref.invalidate(productBatchesProvider(productId)),
        builder: (context, list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.inventory_2_outlined,
              title: 'No batches yet',
              message:
                  'Add an expiry date next time you restock this product and '
                  'it will show up here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) => BatchTile(batch: list[index]),
          );
        },
      ),
    );
  }
}

/// One batch, shared by [ProductBatchesScreen] and the store-wide "expiring soon" list.
class BatchTile extends StatelessWidget {
  const BatchTile({
    required this.batch,
    this.showProductName = false,
    super.key,
  });

  final ProductBatch batch;

  /// True on the store-wide list, where the product isn't already implied by context.
  final bool showProductName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isPast = batch.hasExpiry && batch.expiryDate.isBefore(now);
    final isSoon =
        batch.hasExpiry &&
        !isPast &&
        batch.expiryDate.isBefore(now.add(const Duration(days: 7)));
    final urgentColor = isPast
        ? theme.colorScheme.error
        : (isSoon ? theme.colorScheme.secondary : null);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showProductName
                        ? batch.productName
                        : batch.receivedAt == null
                        ? 'Received on an unknown date'
                        : 'Received ${DateFormat.yMMMd().format(batch.receivedAt!)}',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (urgentColor != null)
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: urgentColor,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${batch.remainingQuantity} of ${batch.initialQuantity} left · '
              '${batch.unitCost.format()} each · worth '
              '${batch.remainingValue.format()}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              !batch.hasExpiry
                  ? 'No expiry'
                  : isPast
                  ? 'Expired ${DateFormat.yMMMd().format(batch.expiryDate)}'
                  : 'Expires ${DateFormat.yMMMd().format(batch.expiryDate)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: urgentColor ?? theme.colorScheme.onSurfaceVariant,
                fontWeight: urgentColor != null ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
