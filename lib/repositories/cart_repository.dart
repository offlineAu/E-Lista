import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/error_mapper.dart';
import '../models/cart.dart';

/// Reads and writes `carts/{uid}`.
///
/// This is the one collection a shopper genuinely owns and writes to directly. Everything
/// in it is advisory: prices in the cart are a preview, and `placeOrder` recomputes them
/// from the catalog. That is why it is safe for the rules to let a client write here while
/// refusing every other write in the database.
///
/// Guests have carts too. "Continue as guest" signs in anonymously, so a guest has a uid
/// and their basket survives closing the app — and follows them, unchanged, when they
/// later create an account against the same uid.
class CartRepository {
  CartRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collectionPath = 'carts';

  DocumentReference<Map<String, Object?>> _cartDocument(String uid) =>
      _firestore.collection(collectionPath).doc(uid);

  /// Streams the cart, emitting [Cart.empty] until one exists.
  Stream<Cart> watch(String uid) {
    return _cartDocument(
      uid,
    ).snapshots().map((snapshot) => Cart.fromJson(snapshot.data()));
  }

  Future<Cart> fetch(String uid) {
    return ErrorMapper.guard(() async {
      final snapshot = await _cartDocument(uid).get();
      return Cart.fromJson(snapshot.data());
    }, operation: 'load your cart');
  }

  /// Replaces the stored cart.
  ///
  /// The whole basket is written at once rather than per-line: a cart is small, and one
  /// document write per change keeps the local state and the stored state from diverging
  /// halfway through an edit.
  Future<void> save(String uid, Cart cart) {
    return ErrorMapper.guard(
      () => _cartDocument(uid).set(cart.toJson()),
      operation: 'save your cart',
    );
  }

  /// Empties the cart after an order is placed.
  Future<void> clear(String uid) => save(uid, Cart.empty);
}
