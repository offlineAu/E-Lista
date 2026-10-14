import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../models/payment_method.dart';
import '../../../models/product.dart';
import '../../../routing/app_routes.dart';
import '../../../services/store_functions_service.dart';
import '../../../widgets/barcode_scanner_view.dart';
import '../../../widgets/bouncing_dots.dart';
import '../../../widgets/gcash_qr_payment_card.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/quantity_stepper.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/owner_product_providers.dart';
import '../application/pos_ticket_controller.dart';
import '../application/register_view_providers.dart';
import '../domain/pos_ticket.dart';
import 'widgets/cashier_logout_action.dart';

/// Ringing up a walk-in sale: no cart, no customer account, no status ladder — someone at
/// the counter has already paid by the time the cashier presses Complete sale, so this
/// books straight to a completed order.
///
/// A bottom-nav tab for a cashier, and reachable by an owner who has switched into register
/// view — never pushed, so it has no back arrow of its own.
class PosCheckoutScreen extends ConsumerStatefulWidget {
  const PosCheckoutScreen({super.key});

  @override
  ConsumerState<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends ConsumerState<PosCheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _tenderController = TextEditingController();
  final _customerNameController = TextEditingController();

  String _search = '';
  bool _isSaving = false;
  PlacedWalkInSale? _placedSale;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // The change-due preview has to update on every keystroke, not just on submit.
    _tenderController.addListener(_onTenderChanged);
  }

  void _onSearchChanged() {
    setState(() => _search = _searchController.text.trim().toLowerCase());
  }

  void _onTenderChanged() => setState(() {});

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _tenderController
      ..removeListener(_onTenderChanged)
      ..dispose();
    _customerNameController.dispose();
    super.dispose();
  }

  Future<void> _submit(
    PosTicket ticket,
    PaymentMethod method,
    Money total,
  ) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final tendered = method == PaymentMethod.cash
        ? Money.tryParse(_tenderController.text)
        : null;

    setState(() => _isSaving = true);
    try {
      final placed = await ref
          .read(storeFunctionsProvider)
          .placeWalkInSale(
            ticket: ticket,
            paymentMethod: method,
            amountTendered: tendered,
            customerName: _customerNameController.text,
            expectedTotal: total,
          );
      if (!mounted) return;
      ref.read(posTicketProvider.notifier).clear();
      setState(() {
        _placedSale = placed;
        _isSaving = false;
      });
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
      setState(() => _isSaving = false);
    }
  }

  void _startNewSale() {
    _tenderController.clear();
    _customerNameController.clear();
    setState(() => _placedSale = null);
  }

  void _openScanner() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const _PosScanSheet()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(isOwnerProvider);
    final viewAsCashier = ref.watch(viewAsCashierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.ownerShiftSummary),
            icon: const Icon(Icons.point_of_sale_outlined),
            tooltip: 'End of shift',
          ),
          if (isOwner && viewAsCashier)
            IconButton(
              onPressed: () {
                ref.read(viewAsCashierProvider.notifier).state = false;
                context.go(AppRoutes.ownerDashboard);
              },
              icon: const Icon(Icons.dashboard_outlined),
              tooltip: 'Exit register view',
            ),
          const CashierLogoutAction(),
        ],
      ),
      body: _placedSale != null
          ? _ReceiptView(sale: _placedSale!, onNewSale: _startNewSale)
          : _buildTicketBuilder(context),
    );
  }

  Widget _buildTicketBuilder(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(ownerCatalogProvider);
    final ticket = ref.watch(posTicketProvider);
    final method = ref.watch(selectedPosPaymentMethodProvider);
    final schedule = ref.watch(gcashFeeScheduleProvider).valueOrNull;

    final subtotal = ticket.subtotal(method);
    final fee = method.chargesConvenienceFee && schedule != null
        ? schedule.feeFor(subtotal)
        : Money.zero;
    final total = subtotal + fee;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Find a product',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear',
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _openScanner,
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scan a barcode',
              ),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: AsyncView<List<Product>>(
            value: catalog,
            onRetry: () => ref.invalidate(ownerCatalogProvider),
            builder: (context, products) {
              final matches = products.where((product) {
                if (!product.isPurchasable) return false;
                if (_search.isEmpty) return true;
                return product.name.toLowerCase().contains(_search) ||
                    (product.brand?.toLowerCase().contains(_search) ?? false);
              }).toList();

              if (matches.isEmpty) {
                return const EmptyView(
                  icon: Icons.search_off,
                  title: 'No products match',
                  compact: true,
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final product = matches[index];
                  return ListTile(
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(product.unitPriceLabel(method)),
                    trailing: IconButton(
                      onPressed: () => ref
                          .read(posTicketProvider.notifier)
                          .addProduct(product),
                      icon: const Icon(Icons.add_shopping_cart),
                      tooltip: 'Add to sale',
                    ),
                    onTap: () => ref
                        .read(posTicketProvider.notifier)
                        .addProduct(product),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 5,
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      if (ticket.isEmpty)
                        const EmptyView(
                          icon: Icons.point_of_sale_outlined,
                          title: 'Nothing on this sale yet',
                          message: 'Add products from the list above.',
                          compact: true,
                        )
                      else ...[
                        Text('This sale', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final line in ticket.lines)
                          _TicketLineTile(line: line, method: method),
                      ],
                      const SizedBox(height: 20),
                      Text('Payment', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final option in PaymentMethod.values) ...[
                            if (option != PaymentMethod.values.first)
                              const SizedBox(width: 10),
                            Expanded(
                              child: _PaymentMethodTile(
                                method: option,
                                selected: method == option,
                                enabled: !_isSaving,
                                onTap: () =>
                                    ref
                                            .read(
                                              selectedPosPaymentMethodProvider
                                                  .notifier,
                                            )
                                            .state =
                                        option,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (method == PaymentMethod.gcash && !ticket.isEmpty) ...[
                        const SizedBox(height: 12),
                        GcashQrPaymentCard(amount: total),
                      ],
                      if (method == PaymentMethod.cash) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _tenderController,
                          decoration: const InputDecoration(
                            labelText: 'Amount tendered (₱)',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          enabled: !_isSaving,
                          validator: (value) {
                            final basic = Validators.money(
                              value,
                              field: 'Amount tendered',
                            );
                            if (basic != null) return basic;
                            final tendered = Money.tryParse(value!);
                            if (tendered == null || tendered < total) {
                              return 'That is less than the total, ${total.format()}.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final tendered = Money.tryParse(
                              _tenderController.text,
                            );
                            final change = tendered == null
                                ? null
                                : tendered - total;
                            return Text(
                              change == null
                                  ? 'Change due appears once an amount is entered.'
                                  : change.isNegative
                                  ? 'Short by ${(-change).format()}.'
                                  : 'Change due: ${change.format()}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: change != null && change.isNegative
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _customerNameController,
                        decoration: const InputDecoration(
                          labelText: 'Customer name (optional)',
                          prefixIcon: Icon(Icons.person_outline),
                          helperText:
                              'Shown on the receipt only — this is not an account.',
                        ),
                        textCapitalization: TextCapitalization.words,
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                ),
                // A pinned footer, not part of the scroll — the cashier should never have
                // to scroll to find the total or the button that completes the sale. Hidden
                // while the keyboard is up: its fixed height doesn't shrink with the rest of
                // the screen, so on a typical phone it otherwise leaves almost no room to see
                // and type into the "Amount tendered" field above it.
                if (MediaQuery.viewInsetsOf(context).bottom == 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: GlassCard(
                      borderRadius: BorderRadius.circular(22),
                      child: Column(
                        children: [
                          PriceRow(label: 'Subtotal', amount: subtotal),
                          if (method.chargesConvenienceFee)
                            PriceRow(
                              label: 'GCash convenience fee',
                              amount: fee,
                              note: 'One fee for the whole sale',
                            ),
                          const Divider(height: 20),
                          PriceRow(
                            label: 'Total',
                            amount: total,
                            emphasised: true,
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: _isSaving || !ticket.canCheckout(method)
                                ? null
                                : () => _submit(ticket, method, total),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text('Complete sale · ${total.format()}'),
                          ),
                          if (ticket.hasStockProblem) ...[
                            const SizedBox(height: 8),
                            Text(
                              'One of these lines wants more than is in stock.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One tile in the two-way cash/GCash picker — a filled, bordered tile when selected
/// rather than a radio button, so the choice reads clearly at a glance while ringing up.
class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = method == PaymentMethod.cash
        ? Icons.payments_outlined
        : Icons.account_balance_wallet_outlined;

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                method.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on Product {
  /// A short "₱18 cash" / "₱19 GCash" label for the product picker row.
  String unitPriceLabel(PaymentMethod method) =>
      '${method.unitPrice(this).format()} ${method.label} · $stockQuantity in stock';
}

class _TicketLineTile extends ConsumerWidget {
  const _TicketLineTile({required this.line, required this.method});

  final PosTicketLine line;
  final PaymentMethod method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (line.exceedsStock)
                    Text(
                      'Only ${line.availableStock} in stock',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Unbounded on purpose — going over stock is allowed here and flagged, not
            // blocked; checkout itself refuses a ticket with a stock problem.
            QuantityStepper(
              quantity: line.quantity,
              minimum: 0,
              compact: true,
              semanticLabel: line.productName,
              onChanged: (value) => ref
                  .read(posTicketProvider.notifier)
                  .setQuantity(line.productId, value),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(
                line.lineTotal(method).formatExact(),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: () => ref
                  .read(posTicketProvider.notifier)
                  .removeLine(line.productId),
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptView extends StatelessWidget {
  const _ReceiptView({required this.sale, required this.onNewSale});

  final PlacedWalkInSale sale;
  final VoidCallback onNewSale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = sale.changeDue;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Sale complete', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              sale.orderNumber,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            GlassCard(
              child: Column(
                children: [
                  PriceRow(
                    label: 'Total',
                    amount: sale.total,
                    emphasised: true,
                  ),
                  if (sale.amountTendered != null)
                    PriceRow(
                      label: 'Amount tendered',
                      amount: sale.amountTendered!,
                    ),
                  if (change != null)
                    PriceRow(
                      label: 'Change',
                      amount: change,
                      emphasised: true,
                      amountColor: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onNewSale, child: const Text('New sale')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  context.go(AppRoutes.ownerOrderDetailsFor(sale.orderId)),
              child: const Text('View full receipt'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-screen scanner for adding products to the current sale, one barcode at a time.
///
/// Stays open across scans, same reasoning as the restock scanner: reopening the camera for
/// every item is the difference between scanning a whole basket in seconds and giving up on
/// the feature. Unlike restock, a miss here needs no create-new-product branch — checkout
/// only ever adds what the store already sells, so `findByBarcode`'s default
/// `includeInactive: false` is exactly right.
class _PosScanSheet extends ConsumerStatefulWidget {
  const _PosScanSheet();

  @override
  ConsumerState<_PosScanSheet> createState() => _PosScanSheetState();
}

class _PosScanSheetState extends ConsumerState<_PosScanSheet> {
  bool _isHandlingScan = false;
  int _addedCount = 0;
  String? _lastMessage;

  Future<void> _onBarcode(String barcode) async {
    if (_isHandlingScan) return;
    setState(() => _isHandlingScan = true);

    try {
      final product = await ref
          .read(productRepositoryProvider)
          .findByBarcode(barcode);
      if (!mounted) return;

      if (product == null) {
        setState(() => _lastMessage = 'No product matches that barcode.');
      } else {
        ref.read(posTicketProvider.notifier).addProduct(product);
        setState(() {
          _addedCount++;
          _lastMessage = 'Added ${product.name}.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Could not look that up. Try again.');
    } finally {
      if (mounted) setState(() => _isHandlingScan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan to add'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Done',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: BarcodeScannerView(
              isPaused: _isHandlingScan,
              hint: 'Scan a barcode to add it to this sale.',
              onBarcode: _onBarcode,
            ),
          ),
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: _isHandlingScan
                ? const InlineWaitRow(label: 'Checking stock…')
                : Text(
                    _lastMessage ??
                        (_addedCount == 0
                            ? 'Ready to scan.'
                            : '$_addedCount added to this sale.'),
                    style: theme.textTheme.labelLarge,
                  ),
          ),
        ],
      ),
    );
  }
}
