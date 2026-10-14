import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/shimmer_loading.dart';
import '../../../widgets/state_views.dart';
import '../application/best_sellers_providers.dart';
import '../application/owner_product_providers.dart' show ownerCatalogProvider;
import 'owner_inventory_screen.dart' show showStockMovementSheet;

/// What is actually selling, and what to reorder before it runs out.
///
/// Both lists read the last 30 days of completed orders — storefront and walk-in sales
/// alike — since `sales/` documents alone carry no per-product detail to rank by.
class BestSellersScreen extends ConsumerWidget {
  const BestSellersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final metric = ref.watch(bestSellerMetricProvider);
    final bestSellers = ref.watch(rankedBestSellersProvider);
    final reorderSuggestions = ref.watch(reorderSuggestionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Best sellers'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerSales),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(productSalesStatsProvider)
            ..invalidate(ownerCatalogProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Last 30 days',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final option in BestSellerMetric.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: metric == option,
                    onSelected: (_) =>
                        ref.read(bestSellerMetricProvider.notifier).state =
                            option,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AsyncView<List<ProductSalesStat>>(
              value: bestSellers,
              compact: true,
              onRetry: () => ref.invalidate(productSalesStatsProvider),
              loadingBuilder: (context) => const ShimmerListSkeleton(
                itemCount: 3,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
              ),
              builder: (context, stats) {
                if (stats.isEmpty) {
                  return const EmptyView(
                    compact: true,
                    icon: Icons.insights_outlined,
                    title: 'Nothing sold yet',
                    message:
                        'Completed sales from the last 30 days will be ranked here.',
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < stats.length; i++)
                      _BestSellerTile(
                        rank: i + 1,
                        stat: stats[i],
                        metric: metric,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Text('Reorder suggestions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Selling faster than the stock on hand will keep up with, at the '
              'recent pace.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            AsyncView<List<ReorderSuggestion>>(
              value: reorderSuggestions,
              compact: true,
              loadingBuilder: (context) => const ShimmerListSkeleton(
                itemCount: 2,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
              ),
              builder: (context, suggestions) {
                if (suggestions.isEmpty) {
                  return const EmptyView(
                    compact: true,
                    icon: Icons.check_circle_outline,
                    title: 'Nothing urgent',
                    message:
                        'Every fast-moving product has enough stock for now.',
                  );
                }
                return Column(
                  children: [
                    for (final suggestion in suggestions)
                      _ReorderTile(suggestion: suggestion),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BestSellerTile extends StatelessWidget {
  const _BestSellerTile({
    required this.rank,
    required this.stat,
    required this.metric,
  });

  final int rank;
  final ProductSalesStat stat;
  final BestSellerMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '#$rank',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                stat.productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  metric == BestSellerMetric.revenue
                      ? stat.revenue.format()
                      : '${stat.unitsSold} sold',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  metric == BestSellerMetric.revenue
                      ? '${stat.unitsSold} sold'
                      : stat.revenue.format(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderTile extends StatelessWidget {
  const _ReorderTile({required this.suggestion});

  final ReorderSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysLeft = suggestion.daysOfStockLeft.floor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        child: Row(
          children: [
            Icon(Icons.trending_up, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Selling ~${suggestion.unitsPerDay.toStringAsFixed(1)}/day · '
                    '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} of stock left',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: () => showStockMovementSheet(
                context,
                suggestion.product,
                initialQuantity: suggestion.suggestedQuantity,
              ),
              child: Text('Order ${suggestion.suggestedQuantity}'),
            ),
          ],
        ),
      ),
    );
  }
}
