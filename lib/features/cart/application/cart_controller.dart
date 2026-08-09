import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/cart.dart';
import '../../../models/payment_method.dart';
import '../../../models/product.dart';
import '../../../repositories/cart_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../auth/application/auth_controller.dart';

/// The signed-in shopper's cart, straight from Firestore.
///
/// Guests included: "Continue as guest" signs in anonymously, so a guest has a uid and
/// therefore a cart document like anyone else. Nothing here special-cases them, and that
/// is what makes the basket survive both closing the app and creating an account later.
final cartProvider = StreamProvider<Cart>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(Cart.empty);
  return ref.watch(cartRepositoryProvider).watch(uid);
});

/// Number of units in the cart, for the badge on the navigation bar.
final cartItemCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).valueOrNull?.itemCount ?? 0;
});

/// How many of one product are already in the cart, for the product card and details page.
final cartQuantityProvider = Provider.family<int, String>((ref, productId) {
  return ref.watch(cartProvider).valueOrNull?.quantityOf(productId) ?? 0;
});

/// The payment method the shopper has selected.
///
/// Held here rather than on the checkout screen because the cart totals change with it:
/// choosing GCash in the cart should update the running total immediately, not at
/// checkout.
final selectedPaymentMethodProvider = StateProvider<PaymentMethod>(
  (ref) => PaymentMethod.cash,
);

/// Changes to the cart.
///
/// Every mutation reads the current cart, applies a pure transformation from [Cart], and
/// writes the result back. The stream then delivers the new value, so the UI has exactly
/// one source of truth and cannot show a quantity that was never stored.
class CartController {
  CartController(this._carts, this._products, this._uid);

  final CartRepository _carts;
  final ProductRepository _products;
  final String? _uid;

  bool get _canWrite => _uid != null;

  /// Adds a product, merging with any line already there.
  Future<void> add(Product product, {int quantity = 1}) async {
    if (!_canWrite) return;
    final cart = await _carts.fetch(_uid!);
    await _carts.save(_uid, cart.addProduct(product, quantity: quantity));
  }

  Future<void> setQuantity(String productId, int quantity) async {
    if (!_canWrite) return;
    final cart = await _carts.fetch(_uid!);
    await _carts.save(_uid, cart.updateQuantity(productId, quantity));
  }

  Future<void> remove(String productId) async {
    if (!_canWrite) return;
    final cart = await _carts.fetch(_uid!);
    await _carts.save(_uid, cart.removeProduct(productId));
  }

  Future<void> clear() async {
    if (!_canWrite) return;
    await _carts.clear(_uid!);
  }

  /// Re-reads every product in the cart and updates the stored prices, stock and
  /// availability.
  ///
  /// Called when the cart screen opens. The refreshed figures are still only a preview —
  /// `placeOrder` recomputes everything server-side — but showing a shopper a price that
  /// changed last week and then charging today's is worse than a moment's delay.
  Future<void> refreshFromCatalog() async {
    if (!_canWrite) return;
    final cart = await _carts.fetch(_uid!);
    if (cart.isEmpty) return;

    final byId = await _products.fetchMany(
      cart.items.map((item) => item.productId),
    );
    final refreshed = cart.refreshedFrom(byId);
    await _carts.save(_uid, refreshed);
  }
}

final cartControllerProvider = Provider<CartController>((ref) {
  return CartController(
    ref.watch(cartRepositoryProvider),
    ref.watch(productRepositoryProvider),
    ref.watch(currentUidProvider),
  );
});
