import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/payment_method.dart';
import '../../../models/product.dart';
import '../domain/pos_ticket.dart';

/// The sale a cashier is currently building at the register.
///
/// `autoDispose`: leaving the checkout screen drops whatever was on the ticket rather than
/// let it silently reappear next visit with stock numbers that may no longer be current.
class PosTicketController extends StateNotifier<PosTicket> {
  PosTicketController() : super(const PosTicket());

  void addProduct(Product product) => state = state.addOrIncrement(product);

  void setQuantity(String productId, int quantity) =>
      state = state.updateQuantity(productId, quantity);

  void removeLine(String productId) => state = state.removeLine(productId);

  void clear() => state = const PosTicket();
}

final posTicketProvider =
    StateNotifierProvider.autoDispose<PosTicketController, PosTicket>(
      (ref) => PosTicketController(),
    );

/// The payment method chosen for the ticket currently being built.
///
/// Scoped to the register screen, separately from `selectedPaymentMethodProvider` in
/// `cart_controller.dart`: a cashier ringing up a walk-in sale is not the same choice as
/// whatever payment method they last picked for their own cart.
final selectedPosPaymentMethodProvider = StateProvider.autoDispose<PaymentMethod>(
  (ref) => PaymentMethod.cash,
);
