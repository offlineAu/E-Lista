import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../models/cart.dart';
import '../../../models/order.dart';
import '../../../models/payment_method.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/gcash_qr_payment_card.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../application/checkout_controller.dart';

/// Confirming an order: who it is for, how it is being paid, and what it costs.
///
/// The totals shown here are a preview. Pressing Place order sends the cart and that
/// figure to the server, which re-derives everything and refuses if they no longer match.
/// This screen never shows a confirmation until the server has written the order.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  bool _isDelivery = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentSessionProvider)?.profile;
    _nameController = TextEditingController(text: profile?.displayName ?? '');
    _phoneController = TextEditingController(text: profile?.phoneNumber ?? '');
    _addressController = TextEditingController(text: profile?.address ?? '');
    _notesController = TextEditingController();
    _isDelivery = profile?.address?.trim().isNotEmpty ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder(Cart cart, CheckoutTotals totals) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final contact = OrderContact(
      name: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      address: _isDelivery ? _addressController.text.trim() : null,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    try {
      final placed = await ref
          .read(checkoutControllerProvider.notifier)
          .placeOrder(
            cart: cart,
            paymentMethod: ref.read(selectedPaymentMethodProvider),
            contact: contact,
            expectedTotal: totals.total,
          );
      if (!mounted) return;
      context.go(AppRoutes.orderConfirmationFor(placed.orderId));
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider).valueOrNull;
    final totals = ref.watch(checkoutTotalsProvider);
    final method = ref.watch(selectedPaymentMethodProvider);
    final isSubmitting =
        ref.watch(checkoutControllerProvider) is CheckoutSubmitting;

    if (cart == null || totals == null) {
      return const Scaffold(body: LoadingView(message: 'Preparing checkout…'));
    }

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: EmptyView(
          icon: Icons.shopping_cart_outlined,
          title: 'Your cart is empty',
          message: 'Add something before checking out.',
          action: FilledButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Back to the shop'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.cart),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to cart',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('Your details', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              enabled: !isSubmitting,
              validator: Validators.personName,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: Icon(Icons.phone_outlined),
                helperText: 'So the store can reach you about this order.',
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              enabled: !isSubmitting,
              validator: Validators.phoneNumber,
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              value: _isDelivery,
              onChanged: isSubmitting
                  ? null
                  : (value) => setState(() => _isDelivery = value),
              title: const Text('Deliver this order'),
              subtitle: Text(
                _isDelivery
                    ? 'We will bring it to the address below.'
                    : 'You will pick this up at the store.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (_isDelivery) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Delivery address',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                enabled: !isSubmitting,
                validator: (value) => _isDelivery
                    ? Validators.required(value, field: 'Address')
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes for the store (optional)',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              enabled: !isSubmitting,
            ),
            const SizedBox(height: 28),
            Text('Payment', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            RadioGroup<PaymentMethod>(
              groupValue: method,
              onChanged: (value) {
                // Ignore taps while the order is in flight: the method is part of what
                // was already sent to the server.
                if (value == null || isSubmitting) return;
                ref.read(selectedPaymentMethodProvider.notifier).state = value;
              },
              child: Column(
                children: [
                  for (final option in PaymentMethod.values)
                    RadioListTile<PaymentMethod>(
                      value: option,
                      title: Text(option.label),
                      subtitle: Text(option.description),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            if (method == PaymentMethod.gcash) ...[
              const SizedBox(height: 16),
              GcashQrPaymentCard(amount: totals.total),
            ],
            const SizedBox(height: 24),
            Text('Order summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final item in cart.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.quantity} × ${item.productName}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.lineTotal(method).formatExact(),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 20),
                    PriceRow(label: 'Subtotal', amount: totals.subtotal),
                    if (method.chargesConvenienceFee)
                      PriceRow(
                        label: 'GCash convenience fee',
                        amount: totals.convenienceFee,
                        note:
                            'One fee for the whole order'
                            '${totals.feeRangeLabel == null ? '' : ' · ${totals.feeRangeLabel}'}',
                      ),
                    const Divider(height: 20),
                    PriceRow(
                      label: '${method.label} total',
                      amount: totals.total,
                      emphasised: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The store confirms the final amount when it accepts your order. '
              'If a price changed while you were shopping we will tell you before '
              'anything is charged.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: isSubmitting || !cart.canCheckout
                  ? null
                  : () => _placeOrder(cart, totals),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text('Place order · ${totals.total.format()}'),
            ),
          ],
        ),
      ),
    );
  }
}
