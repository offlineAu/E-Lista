import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/product_card.dart';
import '../../../widgets/state_views.dart';
import '../../cart/application/cart_controller.dart';

/// The search term, debounced by the screen before it lands here.
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Search results for the current term.
///
/// Empty term means no query at all, not an empty result — the screen shows suggestions
/// instead of "nothing found", which would be both wrong and discouraging.
final searchResultsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.length < 2) return const [];
  return ref.watch(productRepositoryProvider).search(query);
});

/// Search by product name, brand, category or barcode.
///
/// Typing is debounced so a five-letter word costs one Firestore query rather than five.
/// A run of digits is treated as a barcode and answered exactly, which is what makes
/// typing the number off a pack work as well as scanning it.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.text.isEmpty) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).state = value;
    });
    setState(() {}); // Refresh the clear button.
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    _focusNode.requestFocus();
    setState(() {});
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
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Product, brand or barcode',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _clear,
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear search',
                  ),
          ),
          onChanged: _onChanged,
          onSubmitted: (value) {
            _debounce?.cancel();
            ref.read(searchQueryProvider.notifier).state = value;
          },
        ),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.customerScan),
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan a barcode',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: query.trim().length < 2
          ? const _SearchSuggestions()
          : AsyncView<List<Product>>(
              value: results,
              loadingMessage: 'Searching…',
              onRetry: () => ref.invalidate(searchResultsProvider),
              builder: (context, products) {
                if (products.isEmpty) {
                  return EmptyView(
                    icon: Icons.search_off,
                    title: 'No products found',
                    message:
                        'Nothing matches "$query". '
                        'Try another product name, a brand, or a category.',
                    action: TextButton(
                      onPressed: _clear,
                      child: const Text('Clear search'),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: products.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _SearchResultTile(
                      product: product,
                      onTap: () =>
                          context.go(AppRoutes.productDetailsFor(product.id)),
                      onAdd: () => _addToCart(product),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _SearchSuggestions extends ConsumerWidget {
  const _SearchSuggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Search the store', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Type at least two letters. You can search by product name, brand, '
          'category, or the barcode printed on the pack.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text('Try', style: theme.textTheme.labelLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final example in const [
              'Piattos',
              'Coke',
              'Lucky Me',
              'Shampoo',
              'Cheese',
            ])
              ActionChip(
                label: Text(example),
                onPressed: () =>
                    ref.read(searchQueryProvider.notifier).state = example,
              ),
          ],
        ),
      ],
    );
  }
}

class _SearchResultTile extends ConsumerWidget {
  const _SearchResultTile({
    required this.product,
    required this.onTap,
    required this.onAdd,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final inCart = ref.watch(cartQuantityProvider(product.id));

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
                  width: 78,
                  height: 78,
                  child: ProductImage(product: product, iconSize: 26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.brand != null && product.brand!.isNotEmpty)
                      Text(
                        product.brand!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    const SizedBox(height: 8),
                    DualPriceView(
                      cashPrice: product.cashPrice,
                      gcashPrice: product.gcashBasePrice,
                      compact: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filled(
                    onPressed: product.isPurchasable ? onAdd : null,
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    tooltip: product.isPurchasable
                        ? 'Add to cart'
                        : 'Out of stock',
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.tertiary,
                      foregroundColor: theme.colorScheme.onTertiary,
                    ),
                  ),
                  if (inCart > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '$inCart in cart',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
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
