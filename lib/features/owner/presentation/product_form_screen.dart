import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/percentage.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../models/category.dart';
import '../../../models/pricing_settings.dart';
import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../services/product_catalog_service.dart';
import '../../../services/product_image_service.dart';
import '../../../services/store_functions_service.dart';
import '../../../widgets/expiry_date_field.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../../pricing/domain/pricing_engine.dart';
import '../../products/application/catalog_controller.dart';
import '../application/owner_product_providers.dart';

/// Add or edit a product.
///
/// The owner enters what they paid and how much profit they want; the two selling prices
/// are shown live as they type and are computed by the same rules the server will apply
/// when the form is saved. Nothing on this screen sends a price — sending one would make
/// it possible for the catalog to disagree with the store's pricing policy.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({
    super.key,
    this.productId,
    this.prefillBarcode,
    this.imported,
  });

  /// Null when adding.
  final String? productId;

  /// A barcode that was scanned and had no product, so the form opens ready for it.
  final String? prefillBarcode;

  /// A record imported from the external catalog, used to prefill the descriptive fields.
  /// Its price fields are absent by construction — a catalog does not know what this store
  /// paid.
  final CatalogProduct? imported;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _costController = TextEditingController();
  final _profitController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _thresholdController = TextEditingController(text: '5');
  final _unitController = TextEditingController(text: 'pc');

  String? _categoryId;
  PricingMode _pricingMode = PricingMode.standard;
  DateTime? _expiryDate;
  bool _isActive = true;
  bool _isSaving = false;
  bool _hasLoadedExisting = false;

  /// A photo chosen but not yet uploaded. It goes to Storage only once the product is
  /// saved, so abandoning the form never leaves an orphaned file in the bucket.
  PickedProductImage? _pickedImage;

  /// The photo currently on the product, or the one the import brought over.
  String? _imageUrl;

  bool get _isEditing => widget.productId != null;

  @override
  void initState() {
    super.initState();

    final imported = widget.imported;
    if (imported != null) {
      _nameController.text = imported.name;
      _brandController.text = imported.brand ?? '';
      _barcodeController.text = imported.barcode;
      _descriptionController.text = imported.description ?? '';
      _imageUrl = imported.imageUrl;
    }
    if (widget.prefillBarcode != null) {
      _barcodeController.text = widget.prefillBarcode!;
    }

    for (final controller in [_costController, _profitController]) {
      controller.addListener(_onPricingInputChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _brandController,
      _barcodeController,
      _descriptionController,
      _costController,
      _profitController,
      _stockController,
      _thresholdController,
      _unitController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onPricingInputChanged() => setState(() {});

  /// Fills the form from the stored product the first time its data arrives.
  void _loadExisting(OwnerProduct owner) {
    if (_hasLoadedExisting) return;
    _hasLoadedExisting = true;

    final product = owner.product;
    _nameController.text = product.name;
    _brandController.text = product.brand ?? '';
    _barcodeController.text = product.barcode ?? '';
    _descriptionController.text = product.description ?? '';
    _unitController.text = product.unit;
    _thresholdController.text = '${product.lowStockThreshold}';
    _stockController.text = '${product.stockQuantity}';
    _categoryId = product.categoryId;
    _isActive = product.isActive;
    _imageUrl = product.imageUrl;

    _costController.text = owner.cost.costPrice.isZero
        ? ''
        : (owner.cost.costPrice.centavos / Money.centavosPerPeso)
              .toStringAsFixed(2);
    _pricingMode = owner.cost.pricingMode;
    final custom = owner.cost.profitPercentage;
    if (custom != null) {
      _profitController.text = custom.format().replaceAll('%', '');
    }
  }

  Money? get _cost => Money.tryParse(_costController.text);

  Percentage? _effectiveProfit(PricingSettings settings) {
    if (_pricingMode == PricingMode.custom) {
      return Percentage.tryParse(_profitController.text);
    }
    return settings.defaultProfitPercentage;
  }

  ProductPrices? _previewPrices(PricingSettings settings) {
    final cost = _cost;
    final profit = _effectiveProfit(settings);
    if (cost == null || profit == null) return null;
    if (cost.isNegative || profit.isNegative || profit.isAtLeastWhole) {
      return null;
    }
    return PricingEngine.pricesFor(cost: cost, profitPercentage: profit);
  }

  /// Sends the form to `saveProduct`.
  ///
  /// Gathered in one place because saving happens twice when a photo is attached, and the
  /// two calls must agree about every other field.
  Future<SavedProduct> _submit({
    required String? productId,
    required Money cost,
    required String? imageUrl,
    int? initialStock,
    DateTime? expiryDate,
  }) {
    String? trimmedOrNull(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    return ref
        .read(storeFunctionsProvider)
        .saveProduct(
          productId: productId,
          name: _nameController.text.trim(),
          costPrice: cost,
          pricingMode: _pricingMode,
          profitPercentage: _pricingMode == PricingMode.custom
              ? Percentage.tryParse(_profitController.text)
              : null,
          barcode: trimmedOrNull(_barcodeController),
          brand: trimmedOrNull(_brandController),
          categoryId: _categoryId,
          description: trimmedOrNull(_descriptionController),
          imageUrl: imageUrl,
          unit: _unitController.text.trim(),
          source: widget.imported != null ? 'catalogImport' : 'manual',
          lowStockThreshold: int.tryParse(_thresholdController.text) ?? 0,
          initialStock: initialStock,
          expiryDate: expiryDate,
          isActive: _isActive,
        );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final cost = _cost;
    if (cost == null) return;

    setState(() => _isSaving = true);
    try {
      // Save first, upload second: the photo's path is keyed on the product id, so the id
      // has to exist before the file does. A failed save therefore never leaves an
      // orphaned image in the bucket.
      var saved = await _submit(
        productId: widget.productId,
        cost: cost,
        imageUrl: _imageUrl,
        initialStock: _isEditing
            ? null
            : (int.tryParse(_stockController.text) ?? 0),
        expiryDate: _isEditing ? null : _expiryDate,
      );

      final picked = _pickedImage;
      if (picked != null) {
        final url = await ref
            .read(productImageServiceProvider)
            .upload(picked, productId: saved.productId);
        // Second save, this time with the URL. Stock is deliberately not passed again —
        // it would be counted as a fresh opening balance.
        saved = await _submit(
          productId: saved.productId,
          cost: cost,
          imageUrl: url,
        );
      }

      if (!mounted) return;
      ref
        ..invalidate(ownerCatalogProvider)
        ..invalidate(ownerProductProvider(saved.productId));

      showSuccessSnackBar(
        context,
        _isEditing
            ? 'Saved. Cash ${saved.cashPrice.format()}, '
                  'GCash ${saved.gcashBasePrice.format()}.'
            : 'Added. Cash ${saved.cashPrice.format()}, '
                  'GCash ${saved.gcashBasePrice.format()}.',
      );
      context.go(AppRoutes.ownerProducts);
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickPhoto({required bool fromCamera}) async {
    try {
      final picked = await ref
          .read(productImageServiceProvider)
          .pick(fromCamera: fromCamera);
      if (picked == null || !mounted) return;
      setState(() => _pickedImage = picked);
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    }
  }

  void _removePhoto() {
    setState(() {
      _pickedImage = null;
      _imageUrl = null;
    });
  }

  Future<void> _toggleActive(bool value) async {
    final productId = widget.productId;
    if (productId == null) {
      setState(() => _isActive = value);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(storeFunctionsProvider)
          .setProductActive(productId: productId, isActive: value);
      if (!mounted) return;
      setState(() => _isActive = value);
      ref.invalidate(ownerCatalogProvider);
      showSuccessSnackBar(
        context,
        value
            ? 'Product is back on the shelves.'
            : 'Product hidden from customers.',
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productId = widget.productId;

    if (productId == null) return _buildForm(context);

    final existing = ref.watch(ownerProductProvider(productId));
    return AsyncView<OwnerProduct>(
      value: existing,
      onRetry: () => ref.invalidate(ownerProductProvider(productId)),
      builder: (context, owner) {
        _loadExisting(owner);
        return _buildForm(context, existing: owner);
      },
    );
  }

  Widget _buildForm(BuildContext context, {OwnerProduct? existing}) {
    final theme = Theme.of(context);
    final settings =
        ref.watch(pricingSettingsProvider).valueOrNull ??
        PricingSettings.defaults;
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final preview = _previewPrices(settings);
    final imported = widget.imported;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit product' : 'Add product'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerProducts),
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
        ),
        actions: [
          if (_isEditing) ...[
            IconButton(
              onPressed: () => context.go(
                AppRoutes.ownerProductBatchesFor(widget.productId!),
              ),
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Batches',
            ),
            IconButton(
              onPressed: () =>
                  context.go(AppRoutes.ownerPriceHistoryFor(widget.productId!)),
              icon: const Icon(Icons.history),
              tooltip: 'Price history',
            ),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (imported != null)
              _ImportedBanner(imported: imported, theme: theme),
            if (imported != null) const SizedBox(height: 20),

            Text('Product', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Product name',
                prefixIcon: Icon(Icons.label_outline),
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_isSaving,
              validator: Validators.productName,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _brandController,
              decoration: const InputDecoration(
                labelText: 'Brand (optional)',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _barcodeController,
              decoration: const InputDecoration(
                labelText: 'Barcode (optional)',
                prefixIcon: Icon(Icons.qr_code_2),
                helperText:
                    'Scanning this barcode later will find this product.',
              ),
              keyboardType: TextInputType.number,
              enabled: !_isSaving,
              validator: Validators.barcode,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(child: Text('No category')),
                for (final ProductCategory category in categories)
                  DropdownMenuItem<String?>(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Sold by',
                prefixIcon: Icon(Icons.straighten),
                helperText: 'For example pc, pack, sachet, bottle.',
              ),
              enabled: !_isSaving,
              validator: Validators.unit,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              enabled: !_isSaving,
            ),

            const SizedBox(height: 20),
            _PhotoPicker(
              picked: _pickedImage,
              imageUrl: _imageUrl,
              isBusy: _isSaving,
              onPick: _pickPhoto,
              onRemove: _removePhoto,
            ),

            const SizedBox(height: 28),
            Text('Cost and pricing', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Enter what you actually paid, from the receipt. '
              'Selling prices are worked out from it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _costController,
              decoration: const InputDecoration(
                labelText: 'Cost price (₱)',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              enabled: !_isSaving,
              validator: Validators.costPrice,
            ),
            const SizedBox(height: 20),
            SegmentedButton<PricingMode>(
              segments: const [
                ButtonSegment(
                  value: PricingMode.standard,
                  label: Text('Store default'),
                  icon: Icon(Icons.store_outlined),
                ),
                ButtonSegment(
                  value: PricingMode.custom,
                  label: Text('Custom'),
                  icon: Icon(Icons.tune),
                ),
              ],
              selected: {_pricingMode},
              showSelectedIcon: false,
              onSelectionChanged: _isSaving
                  ? null
                  : (selection) =>
                        setState(() => _pricingMode = selection.first),
            ),
            const SizedBox(height: 12),
            if (_pricingMode == PricingMode.standard)
              _StoreDefaultNote(settings: settings, theme: theme)
            else
              TextFormField(
                controller: _profitController,
                decoration: const InputDecoration(
                  labelText: 'Profit for this product (%)',
                  prefixIcon: Icon(Icons.percent),
                  helperText:
                      'Only this product uses it. '
                      'Changing the store default will not move it.',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: !_isSaving,
                validator: _pricingMode == PricingMode.custom
                    ? Validators.profitPercentage
                    : null,
              ),

            const SizedBox(height: 20),
            _PricePreview(prices: preview, cost: _cost, theme: theme),

            const SizedBox(height: 28),
            Text('Stock', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (!_isEditing) ...[
              TextFormField(
                controller: _stockController,
                decoration: const InputDecoration(
                  labelText: 'Starting stock',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  helperText: 'How many you have on the shelf right now.',
                ),
                keyboardType: TextInputType.number,
                enabled: !_isSaving,
                validator: (value) =>
                    Validators.stockQuantity(value, field: 'Starting stock'),
              ),
              const SizedBox(height: 8),
              ExpiryDateField(
                onChanged: (date) => setState(() => _expiryDate = date),
              ),
            ] else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(
                    '${existing?.product.stockQuantity ?? 0} in stock',
                  ),
                  subtitle: const Text(
                    'Stock changes are recorded in the inventory, not here.',
                  ),
                  trailing: TextButton(
                    onPressed: () => context.go(AppRoutes.ownerInventory),
                    child: const Text('Inventory'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _thresholdController,
              decoration: const InputDecoration(
                labelText: 'Tell me when stock drops to',
                prefixIcon: Icon(Icons.notifications_outlined),
                helperText:
                    'This product appears in Low stock at or below this.',
              ),
              keyboardType: TextInputType.number,
              enabled: !_isSaving,
              validator: Validators.lowStockThreshold,
            ),

            if (_isEditing) ...[
              const SizedBox(height: 24),
              SwitchListTile(
                value: _isActive,
                onChanged: _isSaving ? null : _toggleActive,
                title: const Text('Show to customers'),
                subtitle: Text(
                  _isActive
                      ? 'Customers can see and buy this.'
                      : 'Hidden from the shop. Past orders keep their prices.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_isEditing ? 'Save changes' : 'Add product'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The product photo: what it is now, and how to change it.
///
/// A photo is optional throughout. Plenty of a sari-sari store's stock is repacked or
/// unbranded, and demanding a picture before a product can be sold would be the wrong
/// trade — the catalog falls back to a clear placeholder instead.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.picked,
    required this.imageUrl,
    required this.isBusy,
    required this.onPick,
    required this.onRemove,
  });

  final PickedProductImage? picked;
  final String? imageUrl;
  final bool isBusy;
  final void Function({required bool fromCamera}) onPick;
  final VoidCallback onRemove;

  bool get _hasPhoto => picked != null || (imageUrl?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photo', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Optional. Customers see this on the shelf card.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: _preview(theme),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: isBusy
                                ? null
                                : () => onPick(fromCamera: true),
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                            ),
                            label: const Text('Camera'),
                          ),
                          OutlinedButton.icon(
                            onPressed: isBusy
                                ? null
                                : () => onPick(fromCamera: false),
                            icon: const Icon(
                              Icons.photo_library_outlined,
                              size: 18,
                            ),
                            label: const Text('Gallery'),
                          ),
                        ],
                      ),
                      if (_hasPhoto)
                        TextButton.icon(
                          onPressed: isBusy ? null : onRemove,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Remove photo'),
                        ),
                      if (picked != null)
                        Text(
                          'New photo ready to upload when you save.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(ThemeData theme) {
    final chosen = picked;
    if (chosen != null) {
      return Image.memory(chosen.bytes, fit: BoxFit.cover);
    }

    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: 240,
        errorWidget: (context, url, error) => _emptyPreview(theme),
      );
    }

    return _emptyPreview(theme);
  }

  Widget _emptyPreview(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Icon(
        Icons.add_a_photo_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ImportedBanner extends StatelessWidget {
  const _ImportedBanner({required this.imported, required this.theme});

  final CatalogProduct imported;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_download_outlined,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Imported from ${imported.source}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The name and picture come from the catalog. '
                    'The cost below must be what you actually paid — no catalog '
                    'knows your supplier price.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
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

class _StoreDefaultNote extends StatelessWidget {
  const _StoreDefaultNote({required this.settings, required this.theme});

  final PricingSettings settings;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.store_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Uses the store default of '
                '${settings.defaultProfitPercentage.format()}. '
                'Changing that in Pricing settings re-prices this product too.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live cash and GCash prices as the owner types.
///
/// Showing both, with the profit each one earns, is what makes the pricing legible: cash
/// and GCash use the same markup and both drop to a whole peso, so the only GCash
/// difference is the convenience fee added once per order.
class _PricePreview extends StatelessWidget {
  const _PricePreview({
    required this.prices,
    required this.cost,
    required this.theme,
  });

  final ProductPrices? prices;
  final Money? cost;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (prices == null || cost == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Enter a cost to see the selling prices.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final cashProfit = prices!.cash - cost!;
    final gcashProfit = prices!.gcashBase - cost!;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selling prices',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            DualPriceView(
              cashPrice: prices!.cash,
              gcashPrice: prices!.gcashBase,
            ),
            const SizedBox(height: 12),
            Text(
              'Cash earns ${cashProfit.format()} a unit — a markup on your cost, '
              'rounded down to a whole peso.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'GCash earns ${gcashProfit.format()} a unit — the same markup as '
              'cash. A convenience fee is added once per order, not per item.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
