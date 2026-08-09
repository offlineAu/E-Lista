import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../models/cart.dart';
import '../../../models/order.dart';
import '../../../models/payment_method.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/store_functions_service.dart';
import '../../auth/application/auth_controller.dart';
import '../../cart/application/cart_controller.dart';

/// Where checkout has got to.
///
/// `idle → submitting → placed` or `idle → submitting → idle` with a failure. There is no
/// state in which the confirmation screen can be reached without the server having
/// actually written the order — which is the point of modelling it explicitly.
sealed class CheckoutState {
  const CheckoutState();
}

class CheckoutIdle extends CheckoutState {
  const CheckoutIdle();
}

class CheckoutSubmitting extends CheckoutState {
  const CheckoutSubmitting();
}

class CheckoutPlaced extends CheckoutState {
  const CheckoutPlaced(this.order);

  final PlacedOrder order;
}

/// Places the order.
///
/// The client sends what is in the cart and the total it showed the customer. The server
/// re-reads every product, re-derives every price and the fee, and refuses the order if
/// the totals disagree. Nothing here decides what anybody pays.
class CheckoutController extends StateNotifier<CheckoutState> {
  CheckoutController(this._functions, this._users, this._uid)
    : super(const CheckoutIdle());

  final StoreFunctionsService _functions;
  final UserRepository _users;
  final String? _uid;

  /// Submits the order. Throws an `AppFailure` the screen can show; the state machine is
  /// for the button, not for error reporting.
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required PaymentMethod paymentMethod,
    required OrderContact contact,
    required Money expectedTotal,
  }) async {
    state = const CheckoutSubmitting();
    try {
      final placed = await _functions.placeOrder(
        cart: cart,
        paymentMethod: paymentMethod,
        contact: contact,
        expectedTotal: expectedTotal,
      );

      // Remember the details for next time. A failure here must not undo a placed order,
      // so it is deliberately not allowed to propagate.
      final uid = _uid;
      if (uid != null) {
        try {
          await _users.rememberCheckoutDetails(
            uid,
            name: contact.name,
            phoneNumber: contact.phoneNumber,
            address: contact.address,
          );
        } catch (_) {
          // The order is placed; saving the address is a convenience, not a requirement.
        }
      }

      if (mounted) state = CheckoutPlaced(placed);
      return placed;
    } catch (error) {
      if (mounted) state = const CheckoutIdle();
      rethrow;
    }
  }

  void reset() {
    if (mounted) state = const CheckoutIdle();
  }
}

final checkoutControllerProvider =
    StateNotifierProvider.autoDispose<CheckoutController, CheckoutState>((ref) {
      return CheckoutController(
        ref.watch(storeFunctionsProvider),
        ref.watch(userRepositoryProvider),
        ref.watch(currentUidProvider),
      );
    });

/// The totals the customer is about to confirm.
///
/// A preview computed from the cart the client holds. The server recomputes all three from
/// its own state; if they differ, the order is refused rather than quietly adjusted.
class CheckoutTotals {
  const CheckoutTotals({
    required this.subtotal,
    required this.convenienceFee,
    required this.total,
    required this.feeRangeLabel,
  });

  final Money subtotal;
  final Money convenienceFee;
  final Money total;

  /// Which fee band applied, e.g. `₱0 – ₱99.99`. Null for cash.
  final String? feeRangeLabel;
}

/// The preview totals for the current cart and payment method.
final checkoutTotalsProvider = Provider<CheckoutTotals?>((ref) {
  final cart = ref.watch(cartProvider).valueOrNull;
  final schedule = ref.watch(gcashFeeScheduleProvider).valueOrNull;
  final method = ref.watch(selectedPaymentMethodProvider);

  if (cart == null || schedule == null) return null;

  final subtotal = cart.subtotal(method);
  final fee = method.chargesConvenienceFee
      ? schedule.feeFor(subtotal)
      : Money.zero;

  return CheckoutTotals(
    subtotal: subtotal,
    convenienceFee: fee,
    total: subtotal + fee,
    feeRangeLabel: method.chargesConvenienceFee
        ? schedule.tierFor(subtotal).rangeLabel
        : null,
  );
});
