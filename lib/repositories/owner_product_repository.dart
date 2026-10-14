import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_failure.dart';
import '../core/errors/error_mapper.dart';
import '../core/money/money.dart';
import '../features/pricing/domain/pricing_engine.dart';
import '../models/price_history_entry.dart';
import '../models/product.dart';
import '../models/product_batch.dart';

/// Owner-side reads of the catalog, including the cost prices customers cannot see.
///
/// Cost lives in `products/{id}/private/pricing`, a document the security rules serve only
/// to an account whose token carries the owner role. That separation is what makes
/// "customers cannot read cost price" a property of the database rather than a habit of
/// the UI.
///
/// Writes are not here. Products are created and re-priced by the `saveProduct` callable
/// so the two selling prices are always derived from cost and policy rather than sent by a
/// client.
class OwnerProductRepository {
  OwnerProductRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _products =>
      _firestore.collection('products');

  DocumentReference<Map<String, Object?>> _pricingDoc(String productId) =>
      _products.doc(productId).collection('private').doc('pricing');

  /// The full catalog for the owner, including deactivated products.
  ///
  /// Ordered by name so the list reads like a shelf rather than like a database.
  Stream<List<Product>> watchAll({
    bool includeInactive = true,
    int limit = 200,
  }) {
    Query<Map<String, Object?>> query = _products;
    if (!includeInactive) {
      query = query.where('isActive', isEqualTo: true);
    }
    return query
        .orderBy('nameLower')
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Product.fromFirestore).toList());
  }

  /// One product's cost and pricing mode.
  Future<ProductCost?> fetchCost(String productId) {
    return ErrorMapper.guard(
      () async {
        final snapshot = await _pricingDoc(productId).get();
        final data = snapshot.data();
        if (data == null) return null;
        return ProductCost.fromJson(productId, data);
      },
      operation: 'load the cost price',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// Streams the cost document, so an edit screen reflects a restock that changed it.
  Stream<ProductCost?> watchCost(String productId) {
    return _pricingDoc(productId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return ProductCost.fromJson(productId, data);
    });
  }

  /// A product together with its cost, which is what every owner screen actually needs.
  Future<OwnerProduct> requireOwnerProduct(String productId) {
    return ErrorMapper.guard(
      () async {
        final snapshot = await _products.doc(productId).get();
        if (!snapshot.exists) {
          throw const AppFailure.notFound('That product could not be found.');
        }
        final product = Product.fromFirestore(snapshot);
        final cost = await fetchCost(productId);

        return OwnerProduct(
          product: product,
          // A product with no cost document is a data problem, not a crash: show it at
          // zero cost so the owner can open it and put the real figure in.
          cost:
              cost ??
              ProductCost(
                productId: productId,
                costPrice: const Money.fromCentavos(0),
                pricingMode: PricingMode.standard,
              ),
        );
      },
      operation: 'load the product',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// The pricing audit trail for one product, newest first.
  Stream<List<PriceHistoryEntry>> watchPriceHistory(
    String productId, {
    int limit = AppConfig.ownerListPageSize,
  }) {
    return _firestore
        .collection('productPriceHistory')
        .where('productId', isEqualTo: productId)
        .orderBy('changedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(PriceHistoryEntry.fromFirestore).toList(),
        );
  }

  /// The whole store's pricing trail, for the audit screen.
  Stream<List<PriceHistoryEntry>> watchAllPriceHistory({int limit = 50}) {
    return _firestore
        .collection('productPriceHistory')
        .orderBy('changedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(PriceHistoryEntry.fromFirestore).toList(),
        );
  }

  /// One product's batches, oldest-expiring first — the same order FEFO sells them in.
  Stream<List<ProductBatch>> watchBatches(
    String productId, {
    int limit = AppConfig.ownerListPageSize,
  }) {
    return _firestore
        .collection('productBatches')
        .where('productId', isEqualTo: productId)
        .orderBy('expiryDate')
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(ProductBatch.fromFirestore).toList(),
        );
  }

  /// Batches, across every product, expiring within [withinDays] and not yet sold through.
  ///
  /// A single-field range query, so it needs no composite index beyond the one
  /// [watchBatches] already relies on. Depleted batches are filtered out client-side rather
  /// than in the query, since "is this batch used up" is a comparison between two fields
  /// Firestore cannot express in one `where`.
  Stream<List<ProductBatch>> watchExpiringSoon({
    int withinDays = 7,
    int limit = 50,
  }) {
    final horizon = Timestamp.fromDate(
      DateTime.now().add(Duration(days: withinDays)),
    );
    return _firestore
        .collection('productBatches')
        .where('expiryDate', isLessThanOrEqualTo: horizon)
        .orderBy('expiryDate')
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ProductBatch.fromFirestore)
              .where((batch) => !batch.isDepleted)
              .toList(),
        );
  }
}
