import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_failure.dart';
import '../core/errors/error_mapper.dart';
import '../models/product.dart';

/// A page of products plus the cursor needed to ask for the next one.
class ProductPage {
  const ProductPage({
    required this.products,
    required this.hasMore,
    this.lastDocument,
  });

  static const ProductPage empty = ProductPage(products: [], hasMore: false);

  final List<Product> products;

  /// False once the catalog has been read to the end, so the list stops asking.
  final bool hasMore;

  /// Cursor for the next query. Opaque to callers.
  final DocumentSnapshot<Map<String, Object?>>? lastDocument;
}

/// Reads and writes `products/{id}` — the customer-visible half of a product.
///
/// Cost prices are **not** here. They live at `products/{id}/private/pricing` and are
/// reached through `OwnerProductRepository`, which owner screens use. Splitting the two is
/// what lets the security rules make `products` world-readable while keeping cost private.
///
/// Every query is bounded. An unbounded `collection('products').snapshots()` would work
/// for a store with forty products and quietly become a bill and a jank source for a store
/// with four thousand.
class ProductRepository {
  ProductRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collectionPath = 'products';

  CollectionReference<Map<String, Object?>> get _products =>
      _firestore.collection(collectionPath);

  /// One page of the active catalog, newest first.
  ///
  /// [startAfter] continues from a previous page's [ProductPage.lastDocument].
  Future<ProductPage> fetchCatalogPage({
    String? categoryId,
    DocumentSnapshot<Map<String, Object?>>? startAfter,
    int limit = AppConfig.catalogPageSize,
  }) {
    return ErrorMapper.guard(
      () async {
        Query<Map<String, Object?>> query = _products.where(
          'isActive',
          isEqualTo: true,
        );

        if (categoryId != null) {
          query = query.where('categoryId', isEqualTo: categoryId);
        }

        query = query.orderBy('nameLower').limit(limit);
        if (startAfter != null) query = query.startAfterDocument(startAfter);

        final snapshot = await query.get();
        return ProductPage(
          products: snapshot.docs.map(Product.fromFirestore).toList(),
          hasMore: snapshot.docs.length == limit,
          lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
        );
      },
      operation: 'load products',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// Streams a single product, for a details screen that should reflect a stock change
  /// while it is open.
  Stream<Product?> watch(String productId) {
    return _products.doc(productId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return Product.fromFirestore(snapshot);
    });
  }

  Future<Product?> fetch(String productId) {
    return ErrorMapper.guard(
      () async {
        final snapshot = await _products.doc(productId).get();
        if (!snapshot.exists) return null;
        return Product.fromFirestore(snapshot);
      },
      operation: 'load this product',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// Reads several products at once, for refreshing a cart.
  ///
  /// Firestore's `whereIn` takes at most 30 values, so this chunks — a cart with 40 lines
  /// is unusual but must not throw.
  Future<Map<String, Product>> fetchMany(Iterable<String> productIds) {
    return ErrorMapper.guard(
      () async {
        final ids = productIds.toSet().toList();
        if (ids.isEmpty) return <String, Product>{};

        final byId = <String, Product>{};
        for (var start = 0; start < ids.length; start += _whereInLimit) {
          final chunk = ids.sublist(
            start,
            (start + _whereInLimit).clamp(0, ids.length),
          );
          final snapshot = await _products
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final document in snapshot.docs) {
            byId[document.id] = Product.fromFirestore(document);
          }
        }
        return byId;
      },
      operation: 'refresh your cart',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// Finds the active product carrying [barcode], or `null`.
  ///
  /// Used by both scanners: the customer's, to jump straight to a product on the shelf,
  /// and the owner's, to decide between restocking an existing product and importing a
  /// new one.
  Future<Product?> findByBarcode(
    String barcode, {
    bool includeInactive = false,
  }) {
    return ErrorMapper.guard(
      () async {
        final normalised = barcode.trim();
        if (normalised.isEmpty) return null;

        Query<Map<String, Object?>> query = _products.where(
          'barcode',
          isEqualTo: normalised,
        );
        if (!includeInactive) {
          query = query.where('isActive', isEqualTo: true);
        }

        final snapshot = await query.limit(1).get();
        if (snapshot.docs.isEmpty) return null;
        return Product.fromFirestore(snapshot.docs.first);
      },
      operation: 'look up that barcode',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// Searches the catalog by name, brand, category or barcode.
  ///
  /// Firestore has no full-text index. A digits-only query is treated as a barcode and
  /// answered exactly; anything else is matched against the prefix tokens stored on each
  /// product, which is what makes "piat" find Piattos without a search service.
  Future<List<Product>> search(
    String rawQuery, {
    int limit = AppConfig.catalogPageSize,
  }) {
    return ErrorMapper.guard(
      () async {
        final query = rawQuery.trim();
        if (query.isEmpty) return <Product>[];

        if (_looksLikeBarcode(query)) {
          final exact = await findByBarcode(query);
          if (exact != null) return [exact];
          // Fall through: a partial barcode is still worth matching as a token.
        }

        final token = Product.normaliseForSearch(query).replaceAll(' ', '');
        if (token.length < 2) return <Product>[];

        final snapshot = await _products
            .where('isActive', isEqualTo: true)
            .where('searchTokens', arrayContains: token)
            .limit(limit)
            .get();

        final results = snapshot.docs.map(Product.fromFirestore).toList();

        // Exact name matches first, then in-stock, then alphabetical: a shopper searching
        // "coke" wants Coke before Coke Zero, and wants what is actually on the shelf.
        final normalisedQuery = Product.normaliseForSearch(query);
        results.sort((a, b) {
          final aExact = Product.normaliseForSearch(a.name) == normalisedQuery
              ? 0
              : 1;
          final bExact = Product.normaliseForSearch(b.name) == normalisedQuery
              ? 0
              : 1;
          if (aExact != bExact) return aExact.compareTo(bExact);

          final aStock = a.isOutOfStock ? 1 : 0;
          final bStock = b.isOutOfStock ? 1 : 0;
          if (aStock != bStock) return aStock.compareTo(bStock);

          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        return results;
      },
      operation: 'search products',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// Products at or below their low-stock threshold.
  ///
  /// Firestore cannot compare two fields in a query, so this reads the products flagged by
  /// the server-maintained `isLowStock` field. That flag is written in the same transaction
  /// as every stock change, so it cannot drift from the quantity.
  Future<List<Product>> fetchLowStock({int limit = 50}) {
    return ErrorMapper.guard(
      () async {
        final snapshot = await _products
            .where('isActive', isEqualTo: true)
            .where('isLowStock', isEqualTo: true)
            .orderBy('stockQuantity')
            .limit(limit)
            .get();
        return snapshot.docs.map(Product.fromFirestore).toList();
      },
      operation: 'check low stock',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// Streams low-stock products for the owner dashboard.
  Stream<List<Product>> watchLowStock({int limit = 20}) {
    return _products
        .where('isActive', isEqualTo: true)
        .where('isLowStock', isEqualTo: true)
        .orderBy('stockQuantity')
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Product.fromFirestore).toList());
  }

  /// Whether [barcode] is already used, so product creation can say so before saving.
  Future<bool> barcodeExists(String barcode, {String? ignoreProductId}) {
    return ErrorMapper.guard(
      () async {
        final snapshot = await _products
            .where('barcode', isEqualTo: barcode.trim())
            .limit(2)
            .get();
        return snapshot.docs.any((document) => document.id != ignoreProductId);
      },
      operation: 'check that barcode',
      timeout: AppConfig.backendTimeout,
    );
  }

  /// Fetches a product, failing with a message rather than returning `null`.
  Future<Product> require(String productId) async {
    final product = await fetch(productId);
    if (product == null) {
      throw const AppFailure.notFound(
        'That product is no longer in the store.',
      );
    }
    return product;
  }

  /// Firestore's cap on values in a `whereIn` clause.
  static const int _whereInLimit = 30;

  static bool _looksLikeBarcode(String query) {
    return query.length >= 8 && RegExp(r'^\d+$').hasMatch(query);
  }
}
