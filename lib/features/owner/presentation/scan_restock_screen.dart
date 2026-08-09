import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../models/inventory_transaction.dart';
import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../services/product_catalog_service.dart';
import '../../../widgets/barcode_scanner_view.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../../products/application/catalog_service_providers.dart';
import '../application/owner_product_providers.dart';

/// One product added during this restock run, for the running list.
class _RestockEntry {
  const _RestockEntry({
    required this.productName,
    required this.quantity,
    required this.newStock,
  });

  final String productName;
  final int quantity;
  final int newStock;
}

/// Continuous barcode restocking: the screen the owner uses when a delivery arrives.
///
/// Scan a pack, type how many arrived, confirm — and the camera is already live for the
/// next one. Reopening the scanner for every product is the difference between restocking
/// a delivery in two minutes and giving up on the feature.
///
/// Three outcomes are handled, in order of how often they happen:
///
/// 1. **The store already sells it.** Add stock, optionally at a new receipt cost, which
///    re-prices the product.
/// 2. **The catalog knows it but the store does not.** Offer to import the description and
///    open the product form with everything but the cost filled in.
/// 3. **Nobody knows it.** Open the product form with the barcode prefilled.
class ScanRestockScreen extends ConsumerStatefulWidget {
  const ScanRestockScreen({super.key});

  @override
  ConsumerState<ScanRestockScreen> createState() => _ScanRestockScreenState();
}

class _ScanRestockScreenState extends ConsumerState<ScanRestockScreen> {
  final List<_RestockEntry> _session = [];
  bool _isHandlingScan = false;

  Future<void> _onBarcode(String barcode) async {
    if (_isHandlingScan) return;
    setState(() => _isHandlingScan = true);

    try {
      final product = await ref
          .read(productRepositoryProvider)
          .findByBarcode(barcode, includeInactive: true);

      if (!mounted) return;

      if (product != null) {
        await _restockExisting(product);
      } else {
        await _offerToCreate(barcode);
      }
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isHandlingScan = false);
    }
  }

  Future<void> _restockExisting(Product product) async {
    final result = await showModalBottomSheet<_RestockEntry>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RestockSheet(product: product),
    );

    if (result == null || !mounted) return;
    setState(() => _session.insert(0, result));
    ref.invalidate(ownerCatalogProvider);
  }

  Future<void> _offerToCreate(String barcode) async {
    // The store has never carried this. Ask the external catalog what it is — and be
    // explicit when the catalog cannot be reached, because "not found" and "could not ask"
    // lead to different next steps.
    CatalogProduct? imported;
    AppFailure? catalogFailure;

    try {
      imported = await ref
          .read(productCatalogServiceProvider)
          .lookupByBarcode(barcode);
    } on CatalogUnavailable catch (failure) {
      catalogFailure = failure;
    } catch (error) {
      catalogFailure = error is AppFailure ? error : const CatalogUnavailable();
    }

    if (!mounted) return;

    final action = await showModalBottomSheet<_NewProductAction>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UnknownProductSheet(
        barcode: barcode,
        imported: imported,
        catalogFailure: catalogFailure,
      ),
    );

    if (action == null || !mounted) return;

    switch (action) {
      case _NewProductAction.importAndAdd:
        context.go(
          AppRoutes.ownerProductNew,
          extra: ProductFormArguments(barcode: barcode, imported: imported),
        );
      case _NewProductAction.addManually:
        context.go(
          AppRoutes.ownerProductNew,
          extra: ProductFormArguments(barcode: barcode),
        );
      case _NewProductAction.skip:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addedCount = _session.fold(0, (sum, entry) => sum + entry.quantity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan restock'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerDashboard),
          icon: const Icon(Icons.close),
          tooltip: 'Done',
        ),
        actions: [
          TextButton(
            onPressed: () => context.go(AppRoutes.ownerDashboard),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: BarcodeScannerView(
              isPaused: _isHandlingScan,
              hint:
                  'Scan a pack, enter how many arrived, then scan the next one.',
              onBarcode: _onBarcode,
            ),
          ),
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              _session.isEmpty
                  ? 'Nothing added yet in this run.'
                  : '$addedCount added across ${_session.length} '
                        '${_session.length == 1 ? 'product' : 'products'} in this run.',
              style: theme.textTheme.labelLarge,
            ),
          ),
          Expanded(
            flex: 2,
            child: _session.isEmpty
                ? const EmptyView(
                    compact: true,
                    icon: Icons.qr_code_scanner,
                    title: 'Ready to scan',
                    message:
                        'Each product you add appears here so you can check '
                        'the delivery as you go.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _session.length,
                    itemBuilder: (context, index) {
                      final entry = _session[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.add_circle_outline),
                        title: Text(
                          entry.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('Now ${entry.newStock} in stock'),
                        trailing: Text(
                          '+${entry.quantity}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
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

/// Arguments handed to the product form when a scan leads into it.
class ProductFormArguments {
  const ProductFormArguments({this.barcode, this.imported});

  final String? barcode;
  final CatalogProduct? imported;
}

enum _NewProductAction { importAndAdd, addManually, skip }

/// How many arrived, and optionally at what cost.
class _RestockSheet extends ConsumerStatefulWidget {
  const _RestockSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_RestockSheet> createState() => _RestockSheetState();
}

class _RestockSheetState extends ConsumerState<_RestockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _costController = TextEditingController();
  bool _updateCost = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final quantity = int.parse(_quantityController.text.trim());
    final cost = _updateCost ? Money.tryParse(_costController.text) : null;

    setState(() => _isSaving = true);
    try {
      final change = await ref
          .read(storeFunctionsProvider)
          .adjustInventory(
            productId: widget.product.id,
            type: InventoryTransactionType.restock,
            quantity: quantity,
            unitCost: cost,
          );
      if (!mounted) return;
      Navigator.of(context).pop(
        _RestockEntry(
          productName: widget.product.name,
          quantity: quantity,
          newStock: change.newStock,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(product.name, style: theme.textTheme.titleLarge),
            if (product.brand != null)
              Text(
                product.brand!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: StockBadge(
                stockQuantity: product.stockQuantity,
                lowStockThreshold: product.lowStockThreshold,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _quantityController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'How many arrived',
                prefixIcon: Icon(Icons.add_box_outlined),
              ),
              keyboardType: TextInputType.number,
              enabled: !_isSaving,
              validator: Validators.movementQuantity,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _updateCost,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _updateCost = value),
              title: const Text('The cost changed'),
              subtitle: const Text(
                'Enter the new receipt cost and the selling prices update with it.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (_updateCost) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(
                  labelText: 'New cost price (₱)',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: !_isSaving,
                validator: _updateCost ? Validators.costPrice : null,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Add to stock'),
            ),
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What to do about a barcode the store does not carry.
class _UnknownProductSheet extends StatelessWidget {
  const _UnknownProductSheet({
    required this.barcode,
    required this.imported,
    required this.catalogFailure,
  });

  final String barcode;
  final CatalogProduct? imported;
  final AppFailure? catalogFailure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New product', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Barcode $barcode is not in your store yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          if (imported != null) ...[
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      imported!.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    if (imported!.brand != null)
                      Text(
                        imported!.brand!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Found in ${imported!.source}. '
                      'You will still enter what you paid for it.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(_NewProductAction.importAndAdd),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Use these details'),
            ),
            const SizedBox(height: 8),
          ] else if (catalogFailure != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        catalogFailure!.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'The product catalog does not have this barcode either. '
                  'Plenty of local goods are not listed anywhere — add it by hand '
                  'and scanning it will find it from now on.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.tonalIcon(
            onPressed: () =>
                Navigator.of(context).pop(_NewProductAction.addManually),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Add it by hand'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_NewProductAction.skip),
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }
}
