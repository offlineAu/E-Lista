import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../routing/app_routes.dart';
import '../../../services/product_catalog_service.dart';
import '../../../widgets/state_views.dart';
import '../../products/application/catalog_service_providers.dart';
import 'scan_restock_screen.dart' show ProductFormArguments;

final _importQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Finding a product in the external catalog and importing its description.
///
/// What is imported is a name, a brand and a picture — never a price. The catalog has no
/// idea what this store paid its supplier, and treating a listed price as a cost would
/// corrupt every profit figure that follows. The form the owner lands on asks for the
/// receipt cost, always.
class ProductImportScreen extends ConsumerStatefulWidget {
  const ProductImportScreen({super.key});

  @override
  ConsumerState<ProductImportScreen> createState() =>
      _ProductImportScreenState();
}

class _ProductImportScreenState extends ConsumerState<ProductImportScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(_importQueryProvider.notifier).state = value;
    });
  }

  void _import(CatalogProduct product) {
    context.go(
      AppRoutes.ownerProductNew,
      extra: ProductFormArguments(barcode: product.barcode, imported: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = ref.watch(_importQueryProvider);
    final service = ref.watch(productCatalogServiceProvider);
    final results = ref.watch(catalogSearchProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import a product'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerProducts),
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search the catalog by name or brand',
                prefixIcon: Icon(Icons.travel_explore),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (value) {
                _debounce?.cancel();
                ref.read(_importQueryProvider.notifier).state = value;
              },
            ),
          ),
          _SourceNote(service: service, theme: theme),
          Expanded(
            child: query.trim().length < 2
                ? const EmptyView(
                    icon: Icons.travel_explore,
                    title: 'Search the product catalog',
                    message:
                        'Type at least two letters. '
                        'Importing brings over the name, brand and picture — '
                        'you enter what you paid.',
                  )
                : AsyncView<List<CatalogProduct>>(
                    value: results,
                    loadingMessage: 'Searching the catalog…',
                    onRetry: () => ref.invalidate(catalogSearchProvider(query)),
                    builder: (context, products) {
                      if (products.isEmpty) {
                        return EmptyView(
                          icon: Icons.search_off,
                          title: 'Nothing found',
                          message:
                              'The catalog has no match for "$query". Plenty of '
                              'local goods are not listed anywhere — you can add '
                              'this product by hand.',
                          action: FilledButton.icon(
                            onPressed: () =>
                                context.go(AppRoutes.ownerProductNew),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Add by hand'),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: products.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) => _CatalogResultTile(
                          product: products[index],
                          onImport: () => _import(products[index]),
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

/// Says where the results come from, so the owner knows what they are trusting.
class _SourceNote extends StatelessWidget {
  const _SourceNote({required this.service, required this.theme});

  final ProductCatalogService service;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isDevelopmentData = !service.isLive || AppConfig.useMockCatalog;

    return Container(
      width: double.infinity,
      color: isDevelopmentData
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        isDevelopmentData
            ? 'Showing local sample data, not a live catalog. '
                  'Do not use these results in a real store.'
            : 'Results come from ${service.displayName}. '
                  'Prices are never imported — you enter what you paid.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: isDevelopmentData
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CatalogResultTile extends StatelessWidget {
  const _CatalogResultTile({required this.product, required this.onImport});

  final CatalogProduct product;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onImport,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.brand != null)
                      Text(
                        product.brand!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        product.barcode,
                        if (product.unit != null) product.unit!,
                        if (product.category != null) product.category!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: onImport,
                child: const Text('Import'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
