import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/product.dart';
import 'price_display.dart';

/// A product on the customer's shelves.
///
/// Shows both prices, because cash and GCash differ and a shopper should not discover that
/// at checkout. Out-of-stock products stay visible but are visibly unavailable rather than
/// hidden — a customer looking for Piattos should learn that the store has it and is out,
/// not conclude the store never sells it.
class ProductCard extends StatelessWidget {
  const ProductCard({
    required this.product,
    required this.onTap,
    super.key,
    this.onAddToCart,
    this.quantityInCart = 0,
  });

  final Product product;
  final VoidCallback onTap;

  /// Adds one to the cart from the grid. Omitted where the card is not actionable.
  final VoidCallback? onAddToCart;

  /// Shown as a badge so a shopper can see what they already picked up.
  final int quantityInCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAvailable = product.isPurchasable;

    return Semantics(
      button: true,
      label:
          '${product.name}. '
          'Cash ${product.cashPrice.format()}. '
          'GCash ${product.gcashBasePrice.format()}. '
          '${isAvailable ? '${product.stockQuantity} in stock' : 'Out of stock'}.',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The image takes whatever height is left after the text and the button,
              // rather than claiming a fixed aspect ratio. A card in a grid has a height
              // decided by the grid; letting the picture absorb the difference is what
              // keeps the layout from overflowing when a name wraps to two lines or the
              // reader has text scaling turned up.
              Expanded(
                child: _ProductImage(
                  product: product,
                  quantityInCart: quantityInCart,
                  isAvailable: isAvailable,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                    const SizedBox(height: 10),
                    DualPriceView(
                      cashPrice: product.cashPrice,
                      gcashPrice: product.gcashBasePrice,
                      compact: true,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isAvailable
                                ? 'per ${product.unit}'
                                : 'Out of stock',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isAvailable
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ),
                        if (onAddToCart != null)
                          _AddButton(
                            onPressed: isAvailable ? onAddToCart : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({
    required this.product,
    required this.quantityInCart,
    required this.isAvailable,
  });

  final Product product;
  final int quantityInCart;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProductImage(product: product),
          if (!isAvailable)
            ColoredBox(color: theme.colorScheme.surface.withValues(alpha: 0.6)),
          if (product.isLowStock && isAvailable)
            Positioned(
              left: 8,
              top: 8,
              child: StockBadge(
                stockQuantity: product.stockQuantity,
                lowStockThreshold: product.lowStockThreshold,
                showQuantity: false,
              ),
            ),
          if (quantityInCart > 0)
            Positioned(
              right: 8,
              top: 8,
              child: _CartBadge(quantity: quantityInCart),
            ),
        ],
      ),
    );
  }
}

/// A product photo, with a branded placeholder when there is none or it fails to load.
///
/// Images come from Firebase Storage over a connection that is often poor, so this never
/// leaves an empty box: it shows a shopping-basket glyph on the store's own surface colour
/// instead, which reads as "no photo" rather than "broken".
class ProductImage extends StatelessWidget {
  const ProductImage({required this.product, super.key, this.iconSize = 36});

  final Product product;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = product.imageUrl;

    if (url == null || url.isEmpty) {
      return _Placeholder(theme: theme, iconSize: iconSize);
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      // Decode to roughly the size actually shown. Product photos from an external
      // catalog can be 2000px wide; decoding those at full size is the fastest way to
      // make a grid stutter on a cheap phone.
      memCacheWidth: 480,
      placeholder: (context, _) =>
          ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
      errorWidget: (context, url, error) =>
          _Placeholder(theme: theme, iconSize: iconSize),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.theme, required this.iconSize});

  final ThemeData theme;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.shopping_basket_outlined,
          size: iconSize,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: AppTheme.minTouchTarget,
      height: AppTheme.minTouchTarget,
      child: IconButton.filled(
        onPressed: onPressed,
        icon: const Icon(Icons.add_shopping_cart, size: 20),
        tooltip: 'Add to cart',
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.tertiary,
          foregroundColor: theme.colorScheme.onTertiary,
        ),
      ),
    );
  }
}

class _CartBadge extends StatelessWidget {
  const _CartBadge({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          '$quantity in cart',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
