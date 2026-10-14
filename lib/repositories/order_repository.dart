import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_failure.dart';
import '../core/errors/error_mapper.dart';
import '../models/order.dart';

/// Reads `orders/{id}`.
///
/// Nothing here writes. Orders are created by the `placeOrder` callable and moved along by
/// `updateOrderStatus`, both of which run server-side so that totals, stock and fees are
/// derived from Firestore rather than from whatever the client sent. The security rules
/// deny client writes to this collection outright, so a "quick" direct write would not
/// work even if someone added one.
class OrderRepository {
  OrderRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collectionPath = 'orders';

  CollectionReference<Map<String, Object?>> get _orders =>
      _firestore.collection(collectionPath);

  /// Streams one order, so a customer watching the tracking screen sees the status change
  /// as the store moves it along.
  Stream<StoreOrder?> watch(String orderId) {
    return _orders.doc(orderId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return StoreOrder.fromFirestore(snapshot);
    });
  }

  Future<StoreOrder> require(String orderId) {
    return ErrorMapper.guard(
      () async {
        final snapshot = await _orders.doc(orderId).get();
        if (!snapshot.exists) {
          throw const AppFailure.notFound('That order could not be found.');
        }
        return StoreOrder.fromFirestore(snapshot);
      },
      operation: 'load that order',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// A customer's own orders, newest first.
  ///
  /// The `customerId` filter is not what keeps orders private — the rules enforce that
  /// independently — but it must be present or the query is rejected.
  Stream<List<StoreOrder>> watchForCustomer(
    String customerId, {
    int limit = AppConfig.ownerListPageSize,
  }) {
    return _orders
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(StoreOrder.fromFirestore).toList(),
        );
  }

  /// A customer's orders that are still being worked on, for the "track your order"
  /// banner on the home screen.
  Stream<List<StoreOrder>> watchActiveForCustomer(String customerId) {
    return _orders
        .where('customerId', isEqualTo: customerId)
        .where(
          'status',
          whereIn: OrderStatus.values
              .where((status) => status.isOpen)
              .map((status) => status.name)
              .toList(),
        )
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(StoreOrder.fromFirestore).toList(),
        );
  }

  /// Every open order, for the owner's queue.
  Stream<List<StoreOrder>> watchOpenOrders({int limit = 50}) {
    return _orders
        .where(
          'status',
          whereIn: OrderStatus.values
              .where((status) => status.isOpen)
              .map((status) => status.name)
              .toList(),
        )
        .orderBy('createdAt')
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(StoreOrder.fromFirestore).toList(),
        );
  }

  /// Orders in a given status, for the owner's filter chips.
  Stream<List<StoreOrder>> watchByStatus(
    OrderStatus status, {
    int limit = AppConfig.ownerListPageSize,
  }) {
    return _orders
        .where('status', isEqualTo: status.name)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(StoreOrder.fromFirestore).toList(),
        );
  }

  /// How many orders are waiting to be confirmed — the dashboard's "pending" figure.
  Stream<int> watchPendingCount() {
    return _orders
        .where('status', isEqualTo: OrderStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Completed orders within a half-open range `[from, to)`.
  ///
  /// `sales/{orderId}` carries only order-level totals — no per-product lines — so
  /// best-sellers and reorder suggestions read the orders themselves and aggregate
  /// [StoreOrder.items] client-side instead.
  Future<List<StoreOrder>> fetchCompletedBetween(DateTime from, DateTime to) {
    return ErrorMapper.guard(
      () async {
        final snapshot = await _orders
            .where('status', isEqualTo: OrderStatus.completed.name)
            .where(
              'completedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(from),
            )
            .where('completedAt', isLessThan: Timestamp.fromDate(to))
            .get();
        return snapshot.docs.map(StoreOrder.fromFirestore).toList();
      },
      operation: 'load completed orders',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// One page of the owner's order history.
  Future<List<StoreOrder>> fetchPage({
    DocumentSnapshot<Map<String, Object?>>? startAfter,
    int limit = AppConfig.ownerListPageSize,
  }) {
    return ErrorMapper.guard(
      () async {
        Query<Map<String, Object?>> query = _orders
            .orderBy('createdAt', descending: true)
            .limit(limit);
        if (startAfter != null) query = query.startAfterDocument(startAfter);

        final snapshot = await query.get();
        return snapshot.docs.map(StoreOrder.fromFirestore).toList();
      },
      operation: 'load orders',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// The owner-only cost snapshot for an order, used to explain a profit figure.
  ///
  /// Returns `null` when the caller is not the owner — the rules refuse the read — so an
  /// owner screen can degrade to hiding the cost breakdown rather than erroring.
  Future<OrderCostSnapshot?> fetchCostSnapshot(String orderId) async {
    try {
      final snapshot = await _orders
          .doc(orderId)
          .collection('private')
          .doc('costs')
          .get();
      final data = snapshot.data();
      if (data == null) return null;
      return OrderCostSnapshot.fromJson(orderId, data);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }
}
