import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../models/price_history_entry.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/state_views.dart';
import '../../orders/presentation/order_history_screen.dart'
    show formatOrderDate;
import '../application/owner_product_providers.dart';

/// What a product has cost and sold for over time.
///
/// A row is appended whenever a cost or a selling price changes, and nothing ever
/// overwrites one. Six months later this is how the owner answers "what were we paying for
/// this in June?" — a question no current-state screen can answer.
///
/// [productId] narrows it to one product; without it, the whole store's trail is shown.
class PriceHistoryScreen extends ConsumerWidget {
  const PriceHistoryScreen({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = productId;
    final entries = id == null
        ? ref.watch(storePriceHistoryProvider)
        : ref.watch(productPriceHistoryProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Price history'),
        leading: IconButton(
          onPressed: () => context.go(
            id == null
                ? AppRoutes.ownerSettings
                : AppRoutes.ownerProductEditFor(id),
          ),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: AsyncView<List<PriceHistoryEntry>>(
        value: entries,
        onRetry: () => id == null
            ? ref.invalidate(storePriceHistoryProvider)
            : ref.invalidate(productPriceHistoryProvider(id)),
        builder: (context, list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.history,
              title: 'No price changes yet',
              message:
                  'Every change to a cost or a selling price is recorded '
                  'here and kept.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _HistoryTile(entry: list[index], showProductName: id == null),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.showProductName});

  final PriceHistoryEntry entry;
  final bool showProductName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rose = entry.costRose;

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
                    showProductName ? entry.productName : entry.reason.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (rose != null)
                  Icon(
                    rose ? Icons.trending_up : Icons.trending_down,
                    size: 18,
                    color: rose
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
              ],
            ),
            if (showProductName)
              Text(
                entry.reason.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 10),
            _ChangeLine(
              label: 'Cost',
              before: entry.oldCostPrice,
              after: entry.newCostPrice,
              theme: theme,
            ),
            _ChangeLine(
              label: 'Cash price',
              before: entry.oldCashPrice,
              after: entry.newCashPrice,
              theme: theme,
            ),
            _ChangeLine(
              label: 'GCash price',
              before: entry.oldGcashPrice,
              after: entry.newGcashPrice,
              theme: theme,
            ),
            const SizedBox(height: 8),
            Text(
              [
                'Profit ${entry.newProfitPercentage.format()}',
                entry.newPricingMode.label,
                if (entry.changedAt != null) formatOrderDate(entry.changedAt!),
                if (entry.changedByName != null) entry.changedByName!,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({
    required this.label,
    required this.before,
    required this.after,
    required this.theme,
  });

  final String label;
  final Money? before;
  final Money after;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final unchanged = before == null || before == after;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (unchanged)
            Text(after.format(), style: theme.textTheme.bodyMedium)
          else ...[
            Text(
              before!.format(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 14),
            const SizedBox(width: 8),
            Text(
              after.format(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
