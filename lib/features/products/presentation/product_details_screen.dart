import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/product_card.dart';
import '../../../widgets/quantity_stepper.dart';
import '../../../widgets/state_views.dart';
import '../../cart/application/cart_controller.dart';
import '../application/catalog_controller.dart';

/// One product, streamed so stock and price stay current while the page is open.
///
/// A customer sees the two prices they can pay, what is left on the shelf, and nothing
/// else about the store's economics. Cost price, profit percentage and price history live
/// in a separate Firestore document the rules will not serve them — this screen could not
/// show them even if it asked.
final productProvider = StreamProvider.autoDispose.family<Product?, String>((
  ref,
  productId,
) {
  return ref.watch(productRepositoryProvider).watch(productId);
});

class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({required this.productId, super.key});

  final String productId;

  @override
  ConsumerState<ProductDetailsScreen> createState() =>
      _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  int _quantity = 1;
  bool _isAdding = false;

  Future<void> _addToCart(Product product) async {
    setState(() => _isAdding = true);
    try {
      await ref.read(cartControllerProvider).add(product, quantity: _quantity);
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        '$_quantity × ${product.name} added to your cart.',
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productProvider(widget.productId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        title: const Text('Product'),
      ),
      body: AsyncView<Product?>(
        value: product,
        onRetry: () => ref.invalidate(productProvider(widget.productId)),
        builder: (context, value) {
          if (value == null) {
            return EmptyView(
              icon: Icons.search_off,
              title: 'Product not found',
              message: 'This product may have been removed from the store.',
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Back to the shop'),
              ),
            );
          }
          return _ProductBody(
            product: value,
            quantity: _quantity,
            isAdding: _isAdding,
            onQuantityChanged: (quantity) =>
                setState(() => _quantity = quantity),
            onAddToCart: () => _addToCart(value),
          );
        },
      ),
    );
  }
}

class _ProductBody extends ConsumerWidget {
  const _ProductBody({
    required this.product,
    required this.quantity,
    required this.isAdding,
    required this.onQuantityChanged,
    required this.onAddToCart,
  });

  final Product product;
  final int quantity;
  final bool isAdding;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final inCart = ref.watch(cartQuantityProvider(product.id));
    final categories = ref.watch(categoriesProvider).valueOrNull;
    final category = _categoryOf(categories);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              AspectRatio(
                aspectRatio: 1.4,
                child: ProductImage(product: product, iconSize: 64),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.brand != null && product.brand!.isNotEmpty)
                      Text(
                        product.brand!,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(product.name, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StockBadge(
                          stockQuantity: product.stockQuantity,
                          lowStockThreshold: product.lowStockThreshold,
                        ),
                        if (category != null)
                          Chip(
                            label: Text(category.name),
                            visualDensity: VisualDensity.compact,
                          ),
                        Chip(
                          label: Text('per ${product.unit}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Price', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 12),
                            DualPriceView(
                              cashPrice: product.cashPrice,
                              gcashPrice: product.gcashBasePrice,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'GCash orders add one small convenience fee per order, '
                              'not per item. You will see it before you confirm.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (product.description != null &&
                        product.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'About this product',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.description!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (product.barcode != null) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Icon(
                            Icons.qr_code_2,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            product.barcode!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (inCart > 0) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(
                            Icons.shopping_cart,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$inCart already in your cart',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go(AppRoutes.cart),
                            child: const Text('View cart'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
        _AddToCartBar(
          product: product,
          quantity: quantity,
          isAdding: isAdding,
          onQuantityChanged: onQuantityChanged,
          onAddToCart: onAddToCart,
        ),
      ],
    );
  }

  ProductCategory? _categoryOf(List<ProductCategory>? categories) {
    if (categories == null || product.categoryId == null) return null;
    for (final category in categories) {
      if (category.id == product.categoryId) return category;
    }
    return null;
  }
}

class _AddToCartBar extends StatelessWidget {
  const _AddToCartBar({
    required this.product,
    required this.quantity,
    required this.isAdding,
    required this.onQuantityChanged,
    required this.onAddToCart,
  });

  final Product product;
  final int quantity;
  final bool isAdding;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canBuy = product.isPurchasable;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: theme.colorScheme.shadow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              QuantityStepper(
                quantity: quantity,
                maximum: product.maximumOrderQuantity,
                enabled: canBuy && !isAdding,
                semanticLabel: product.name,
                onChanged: onQuantityChanged,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed: canBuy && !isAdding ? onAddToCart : null,
                  icon: isAdding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.add_shopping_cart),
                  label: Text(canBuy ? 'Add to cart' : 'Out of stock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
