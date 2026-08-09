import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/product_card.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../products/application/catalog_controller.dart';

/// The shelves.
///
/// A greeting, a search entry point, the category chips and a grid of products with both
/// prices on every card. Scrolling near the bottom fetches the next page, so the list is
/// bounded without the shopper ever seeing a "load more" button.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Start the next page while there is still a screenful to read, so the grid does not
    // visibly stop at the bottom.
    if (position.pixels >= position.maxScrollExtent - 600) {
      ref.read(catalogControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _addToCart(Product product) async {
    try {
      await ref.read(cartControllerProvider).add(product);
      if (!mounted) return;
      showSuccessSnackBar(context, '${product.name} added to your cart.');
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(catalogControllerProvider);
    final session = ref.watch(currentSessionProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(catalogControllerProvider.notifier).refresh(),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              floating: true,
              titleSpacing: 20,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Kumusta, ${session?.greetingName ?? 'there'}!',
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    'What do you need today?',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: () => context.go(AppRoutes.customerScan),
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan a barcode',
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: _SearchBar(onTap: () => context.go(AppRoutes.search)),
              ),
            ),
            const SliverToBoxAdapter(child: _CategoryChips()),
            if (catalog.isLoadingFirstPage)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: LoadingView(message: 'Loading the shelves…'),
              )
            else if (catalog.products.isEmpty && catalog.failure != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(
                  failure: catalog.failure!,
                  onRetry: () =>
                      ref.read(catalogControllerProvider.notifier).refresh(),
                ),
              )
            else if (catalog.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyView(
                  icon: Icons.storefront_outlined,
                  title: ref.watch(selectedCategoryProvider) == null
                      ? 'The shelves are empty'
                      : 'Nothing in this category yet',
                  message: ref.watch(selectedCategoryProvider) == null
                      ? 'The store has not added any products yet. '
                            'Please check back soon.'
                      : 'Try another category, or search for what you need.',
                  action: ref.watch(selectedCategoryProvider) == null
                      ? null
                      : TextButton(
                          onPressed: () =>
                              ref
                                      .read(selectedCategoryProvider.notifier)
                                      .state =
                                  null,
                          child: const Text('Show everything'),
                        ),
                ),
              )
            else
              _ProductGrid(products: catalog.products, onAddToCart: _addToCart),
            if (catalog.isLoadingMore)
              const SliverToBoxAdapter(child: LoadingView(compact: true)),
            if (catalog.failure != null && catalog.products.isNotEmpty)
              SliverToBoxAdapter(
                child: ErrorView(
                  failure: catalog.failure!,
                  compact: true,
                  onRetry: () =>
                      ref.read(catalogControllerProvider.notifier).loadMore(),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Search products',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Text(
                  'Search Piattos, Coke, shampoo…',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);

    return categories.maybeWhen(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: selected == null,
                  onSelected: (_) =>
                      ref.read(selectedCategoryProvider.notifier).state = null,
                ),
              ),
              for (final category in list)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category.name),
                    selected: selected == category.id,
                    onSelected: (isSelected) =>
                        ref.read(selectedCategoryProvider.notifier).state =
                            isSelected ? category.id : null,
                  ),
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox(height: 48),
    );
  }
}

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid({required this.products, required this.onAddToCart});

  final List<Product> products;
  final Future<void> Function(Product product) onAddToCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    // Two columns on a phone, more as the window grows — the same grid serves a tablet
    // and the web build without a second layout.
    final columns = switch (width) {
      < 600 => 2,
      < 900 => 3,
      < 1200 => 4,
      _ => 5,
    };

    // Cards get taller as the reader's text scale goes up, so the name, both prices and
    // the add button keep their room instead of being squeezed out of the card.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final aspectRatio = 0.62 / textScale.clamp(1.0, 1.6);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: aspectRatio,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductCard(
            product: product,
            quantityInCart: ref.watch(cartQuantityProvider(product.id)),
            onTap: () => context.go(AppRoutes.productDetailsFor(product.id)),
            onAddToCart: () => onAddToCart(product),
          );
        },
      ),
    );
  }
}
