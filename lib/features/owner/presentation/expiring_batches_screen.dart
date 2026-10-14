import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/product_batch.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/state_views.dart';
import '../application/owner_product_providers.dart';
import 'product_batches_screen.dart' show BatchTile;

/// Batches expiring within a week, across the whole store.
///
/// The point of FEFO is acting before stock goes to waste, so this is the list that turns
/// "sold oldest-first" into something the owner can actually do something about — a plain
/// list to check before the week's spoilage becomes a write-off.
class ExpiringBatchesScreen extends ConsumerWidget {
  const ExpiringBatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final batches = ref.watch(expiringBatchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expiring soon'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerInventory),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: AsyncView<List<ProductBatch>>(
        value: batches,
        onRetry: () => ref.invalidate(expiringBatchesProvider),
        builder: (context, list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.check_circle_outline,
              title: 'Nothing expiring soon',
              message: 'Batches due within a week will show up here.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              GlassCard(
                child: Row(
                  children: [
                    Icon(
                      Icons.event_busy_outlined,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expiringSoonValue(list).format(),
                            style: theme.textTheme.headlineSmall,
                          ),
                          Text(
                            'at cost, across ${list.length} '
                            '${list.length == 1 ? 'batch' : 'batches'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final batch in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BatchTile(batch: batch, showProductName: true),
                ),
            ],
          );
        },
      ),
    );
  }
}
