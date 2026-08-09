import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../models/inventory_transaction.dart';
import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../application/dashboard_providers.dart';
import '../application/owner_product_providers.dart';

/// Stock on hand, with the low ones first and a way to correct any of them.
///
/// Every correction made here writes a ledger row: an adjustment after a recount, goods
/// written off as damaged or expired, a return. A stock number the owner can silently
/// overwrite is not an inventory, so nothing on this screen edits the quantity directly.
class OwnerInventoryScreen extends ConsumerWidget {
  const OwnerInventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalog = ref.watch(ownerCatalogProvider);
    final lowStock = ref.watch(lowStockProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.ownerInventoryHistory),
            icon: const Icon(Icons.history),
            tooltip: 'Inventory history',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.ownerScanRestock),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan restock'),
      ),
      body: AsyncView<List<Product>>(
        value: catalog,
        onRetry: () => ref.invalidate(ownerCatalogProvider),
        builder: (context, products) {
          if (products.isEmpty) {
            return const EmptyView(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing to count yet',
              message: 'Add a product and its stock will show up here.',
            );
          }

          // Low stock first, then out of stock, then everything else alphabetically:
          // this screen exists to answer "what do I need to order?".
          final sorted = [...products]
            ..sort((a, b) {
              final aUrgent = a.isOutOfStock ? 0 : (a.isLowStock ? 1 : 2);
              final bUrgent = b.isOutOfStock ? 0 : (b.isLowStock ? 1 : 2);
              if (aUrgent != bUrgent) return aUrgent.compareTo(bUrgent);
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (lowStock.isNotEmpty)
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${lowStock.length} '
                            '${lowStock.length == 1 ? 'product needs' : 'products need'} '
                            'restocking.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (lowStock.isNotEmpty) const SizedBox(height: 12),
              for (final product in sorted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _InventoryTile(product: product),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InventoryTile extends ConsumerWidget {
  const _InventoryTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StockBadge(
                        stockQuantity: product.stockQuantity,
                        lowStockThreshold: product.lowStockThreshold,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'alert at ${product.lowStockThreshold}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => showStockMovementSheet(context, product),
              icon: const Icon(Icons.tune),
              tooltip: 'Record a stock movement',
            ),
          ],
        ),
      ),
    );
  }
}

/// Records a stock movement against [product].
///
/// Shared by the inventory list and the product screen so the same rules — a reason for an
/// adjustment, a cost only with a restock — apply wherever stock is touched.
Future<void> showStockMovementSheet(
  BuildContext context,
  Product product,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _StockMovementSheet(product: product),
  );
}

class _StockMovementSheet extends ConsumerStatefulWidget {
  const _StockMovementSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_StockMovementSheet> createState() =>
      _StockMovementSheetState();
}

class _StockMovementSheetState extends ConsumerState<_StockMovementSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _reasonController = TextEditingController();
  final _costController = TextEditingController();

  InventoryTransactionType _type = InventoryTransactionType.restock;
  bool _isDecrease = false;
  bool _updateCost = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final change = await ref
          .read(storeFunctionsProvider)
          .adjustInventory(
            productId: widget.product.id,
            type: _type,
            quantity: int.parse(_quantityController.text.trim()),
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
            unitCost: _updateCost && _type.acceptsCostUpdate
                ? Money.tryParse(_costController.text)
                : null,
            isDecrease:
                _type == InventoryTransactionType.adjustment && _isDecrease,
          );

      if (!mounted) return;
      ref
        ..invalidate(ownerCatalogProvider)
        ..invalidate(lowStockProvider);
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        '${widget.product.name}: now ${change.newStock} in stock.',
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

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.product.name, style: theme.textTheme.titleLarge),
              Text(
                '${widget.product.stockQuantity} in stock now',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<InventoryTransactionType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'What happened',
                  prefixIcon: Icon(Icons.swap_vert),
                ),
                items: [
                  for (final type
                      in InventoryTransactionType.manuallyRecordable)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _type = value;
                          if (!value.acceptsCostUpdate) _updateCost = false;
                        });
                      },
              ),
              if (_type == InventoryTransactionType.adjustment) ...[
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Count went up'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Count went down'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                  ],
                  selected: {_isDecrease},
                  showSelectedIcon: false,
                  onSelectionChanged: _isSaving
                      ? null
                      : (selection) =>
                            setState(() => _isDecrease = selection.first),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: 'How many',
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
                enabled: !_isSaving,
                validator: Validators.movementQuantity,
              ),
              if (_type.requiresReason) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    prefixIcon: Icon(Icons.notes),
                    helperText:
                        'So the history still makes sense in six months.',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  enabled: !_isSaving,
                  validator: (value) =>
                      Validators.required(value, field: 'Reason'),
                ),
              ],
              if (_type.acceptsCostUpdate) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _updateCost,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _updateCost = value),
                  title: const Text('The cost changed'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_updateCost)
                  TextFormField(
                    controller: _costController,
                    decoration: const InputDecoration(
                      labelText: 'New cost price (₱)',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                      helperText: 'Selling prices update to match.',
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
                    : const Text('Record it'),
              ),
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
