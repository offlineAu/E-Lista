import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/product_card.dart';
import '../../../widgets/state_views.dart';
import '../application/owner_product_providers.dart';

/// The owner's catalog: everything the store sells, active or not.
///
/// Cost is deliberately not on the list rows. It is one document per product, and loading
/// a hundred of them to show a column nobody scans would triple the read cost of opening
/// this screen. It appears on the product itself, where the owner is about to use it.
class OwnerProductsScreen extends ConsumerWidget {
  const OwnerProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(filteredOwnerCatalogProvider);
    final query = ref.watch(ownerProductSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.ownerProductImport),
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: 'Import from catalog',
          ),
          IconButton(
            onPressed: () => context.go(AppRoutes.ownerScanRestock),
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan restock',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.ownerProductNew),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search your products',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () =>
                            ref
                                    .read(ownerProductSearchProvider.notifier)
                                    .state =
                                '',
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                      ),
              ),
              onChanged: (value) =>
                  ref.read(ownerProductSearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: AsyncView<List<Product>>(
              value: products,
              onRetry: () => ref.invalidate(ownerCatalogProvider),
              builder: (context, list) {
                if (list.isEmpty) {
                  return EmptyView(
                    icon: Icons.inventory_2_outlined,
                    title: query.isEmpty
                        ? 'No products yet'
                        : 'Nothing matches "$query"',
                    message: query.isEmpty
                        ? 'Scan a barcode to import a product, or add one by hand.'
                        : 'Try a different name, brand or barcode.',
                    action: query.isEmpty
                        ? FilledButton.icon(
                            onPressed: () =>
                                context.go(AppRoutes.ownerScanRestock),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Scan a product'),
                          )
                        : TextButton(
                            onPressed: () =>
                                ref
                                        .read(
                                          ownerProductSearchProvider.notifier,
                                        )
                                        .state =
                                    '',
                            child: const Text('Clear search'),
                          ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) => _OwnerProductTile(
                    product: list[index],
                    onTap: () => context.go(
                      AppRoutes.ownerProductEditFor(list[index].id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerProductTile extends StatelessWidget {
  const _OwnerProductTile({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: ProductImage(product: product, iconSize: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (!product.isActive)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Chip(
                              label: const Text('Hidden'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                      ],
                    ),
                    if (product.brand != null && product.brand!.isNotEmpty)
                      Text(
                        product.brand!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cash ${product.cashPrice.format()}  ·  '
                            'GCash ${product.gcashBasePrice.format()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    StockBadge(
                      stockQuantity: product.stockQuantity,
                      lowStockThreshold: product.lowStockThreshold,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
