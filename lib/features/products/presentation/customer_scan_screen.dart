import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/barcode_scanner_view.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../../cart/application/cart_controller.dart';

/// Scanning a pack in the shop to see what it costs.
///
/// This is product *discovery* and nothing else. It reads the same public catalog a
/// customer can already browse, and it deliberately offers none of the owner's scanner:
/// no stock entry, no cost, no restocking. The two flows share a viewfinder widget and
/// nothing else.
class CustomerScanScreen extends ConsumerStatefulWidget {
  const CustomerScanScreen({super.key});

  @override
  ConsumerState<CustomerScanScreen> createState() => _CustomerScanScreenState();
}

class _CustomerScanScreenState extends ConsumerState<CustomerScanScreen> {
  bool _isLooking = false;

  Future<void> _onBarcode(String barcode) async {
    if (_isLooking) return;
    setState(() => _isLooking = true);

    try {
      final product = await ref
          .read(productRepositoryProvider)
          .findByBarcode(barcode);
      if (!mounted) return;

      if (product == null) {
        await showModalBottomSheet<void>(
          context: context,
          builder: (context) => _NotStockedSheet(barcode: barcode),
        );
      } else {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => _ScannedProductSheet(product: product),
        );
      }
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isLooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a product'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
          icon: const Icon(Icons.close),
          tooltip: 'Close',
        ),
      ),
      body: BarcodeScannerView(
        isPaused: _isLooking,
        hint: 'Point the camera at the barcode to see the price.',
        onBarcode: _onBarcode,
      ),
    );
  }
}

class _ScannedProductSheet extends ConsumerStatefulWidget {
  const _ScannedProductSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_ScannedProductSheet> createState() =>
      _ScannedProductSheetState();
}

class _ScannedProductSheetState extends ConsumerState<_ScannedProductSheet> {
  bool _isAdding = false;

  Future<void> _addToCart() async {
    setState(() => _isAdding = true);
    try {
      await ref.read(cartControllerProvider).add(widget.product);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        '${widget.product.name} added to your cart.',
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
      setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (product.brand != null && product.brand!.isNotEmpty)
            Text(
              product.brand!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          Text(product.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: StockBadge(
              stockQuantity: product.stockQuantity,
              lowStockThreshold: product.lowStockThreshold,
              showQuantity: false,
            ),
          ),
          const SizedBox(height: 20),
          DualPriceView(
            cashPrice: product.cashPrice,
            gcashPrice: product.gcashBasePrice,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: product.isPurchasable && !_isAdding ? _addToCart : null,
            icon: _isAdding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.add_shopping_cart),
            label: Text(product.isPurchasable ? 'Add to cart' : 'Out of stock'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go(AppRoutes.productDetailsFor(product.id));
            },
            child: const Text('See full details'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Scan another'),
          ),
        ],
      ),
    );
  }
}

class _NotStockedSheet extends StatelessWidget {
  const _NotStockedSheet({required this.barcode});

  final String barcode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'The store does not carry this',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Barcode $barcode is not in this store. '
            'Try searching by name — it may be sold under a different pack.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go(AppRoutes.search);
            },
            child: const Text('Search by name'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Scan another'),
          ),
        ],
      ),
    );
  }
}
