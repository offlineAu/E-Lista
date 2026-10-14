import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/aurora_header.dart';
import '../../../widgets/product_card.dart';
import '../../../widgets/shimmer_loading.dart';
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
    final catalog = ref.watch(catalogControllerProvider);
    final session = ref.watch(currentSessionProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(catalogControllerProvider.notifier).refresh(),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: AuroraHeader(
                greeting: 'Kumusta, ${session?.greetingName ?? 'there'}!',
                title: 'What do you need today?',
                height: 170,
                actions: [
                  IconButton(
                    onPressed: () => context.go(AppRoutes.customerScan),
                    icon: const Icon(
                      Icons.qr_code_scanner,
                      color: Colors.white,
                    ),
                    tooltip: 'Scan a barcode',
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: _SearchBar(onTap: () => context.go(AppRoutes.search)),
              ),
            ),
            const SliverToBoxAdapter(child: _PromoBanner()),
            const SliverToBoxAdapter(child: _CategoryChips()),
            const SliverToBoxAdapter(child: _TrendingStrip()),
            if (catalog.isLoadingFirstPage)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ShimmerProductGrid(
                  columns: _columnsForWidth(
                    MediaQuery.sizeOf(context).width,
                  ),
                ),
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

/// A short, always-true reassurance card — no fake discount claims, since the store has no
/// promotions system behind it.
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryRose, AppColors.accentViolet],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Everyday low prices',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Fresh stock, straight from the shelf to you.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal strip of the store's best-selling active products, ranked by a lifetime
/// sold count maintained server-side — a customer cannot list every order the way the
/// owner's own best-sellers screen does, so this reads a public counter instead.
class _TrendingStrip extends ConsumerWidget {
  const _TrendingStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trending = ref.watch(trendingProductsProvider);

    return trending.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (products) {
        if (products.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text('Best sellers', style: theme.textTheme.titleSmall),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 116,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: products.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) =>
                      _TrendingTile(product: products[index]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrendingTile extends StatelessWidget {
  const _TrendingTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 92,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => context.go(AppRoutes.productDetailsFor(product.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              child: SizedBox(
                width: 92,
                height: 72,
                child: ProductImage(product: product, iconSize: 28),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
            Text(
              product.cashPrice.format(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Two columns on a phone, more as the window grows — the same grid serves a tablet and
// the web build without a second layout. Shared with the shimmer skeleton so the first
// load's placeholder count matches the real grid.
int _columnsForWidth(double width) => switch (width) {
  < 600 => 2,
  < 900 => 3,
  < 1200 => 4,
  _ => 5,
};

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid({required this.products, required this.onAddToCart});

  final List<Product> products;
  final Future<void> Function(Product product) onAddToCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = _columnsForWidth(MediaQuery.sizeOf(context).width);

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
