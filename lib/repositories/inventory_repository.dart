import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/app_config.dart';
import '../core/errors/error_mapper.dart';
import '../models/inventory_transaction.dart';

/// Reads `inventoryTransactions/{id}` — the stock ledger.
///
/// Owner-only. Rows are written by Cloud Functions in the same Firestore transaction that
/// changes `products/{id}.stockQuantity`, which is what guarantees the ledger and the
/// balance agree and that two customers cannot both buy the last pack.
class InventoryRepository {
  InventoryRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collectionPath = 'inventoryTransactions';

  CollectionReference<Map<String, Object?>> get _transactions =>
      _firestore.collection(collectionPath);

  /// The whole ledger, newest first, one page at a time.
  Future<List<InventoryTransaction>> fetchPage({
    DocumentSnapshot<Map<String, Object?>>? startAfter,
    int limit = AppConfig.ownerListPageSize,
  }) {
    return ErrorMapper.guard(
      () async {
        Query<Map<String, Object?>> query = _transactions
            .orderBy('createdAt', descending: true)
            .limit(limit);
        if (startAfter != null) query = query.startAfterDocument(startAfter);

        final snapshot = await query.get();
        return snapshot.docs.map(InventoryTransaction.fromFirestore).toList();
      },
      operation: 'load inventory history',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// One product's movements, for the history tab on its edit screen.
  Stream<List<InventoryTransaction>> watchForProduct(
    String productId, {
    int limit = AppConfig.ownerListPageSize,
  }) {
    return _transactions
        .where('productId', isEqualTo: productId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(InventoryTransaction.fromFirestore).toList(),
        );
  }

  /// The latest movements across all products, for the inventory screen's activity feed.
  Stream<List<InventoryTransaction>> watchRecent({int limit = 20}) {
    return _transactions
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(InventoryTransaction.fromFirestore).toList(),
        );
  }

  /// Movements of one kind in a date range — "everything we wrote off as damaged in July".
  Future<List<InventoryTransaction>> fetchByTypeBetween(
    InventoryTransactionType type,
    DateTime from,
    DateTime to,
  ) {
    return ErrorMapper.guard(
      () async {
        final snapshot = await _transactions
            .where('type', isEqualTo: type.name)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(from),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(to))
            .orderBy('createdAt', descending: true)
            .get();
        return snapshot.docs.map(InventoryTransaction.fromFirestore).toList();
      },
      operation: 'load inventory history',
      timeout: AppConfig.backendTimeout,
    );
  }
}
