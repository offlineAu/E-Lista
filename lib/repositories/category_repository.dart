import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/error_mapper.dart';
import '../models/category.dart';

/// Reads `categories/{id}`.
///
/// World-readable, and small enough — a sari-sari store has a dozen shelves, not a
/// thousand — that the whole collection can be streamed without paging.
class CategoryRepository {
  CategoryRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collectionPath = 'categories';

  CollectionReference<Map<String, Object?>> get _categories =>
      _firestore.collection(collectionPath);

  /// Streams the active categories in the order the owner arranged them.
  Stream<List<ProductCategory>> watchActive() {
    return _categories
        .where('isActive', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(ProductCategory.fromFirestore).toList(),
        );
  }

  Future<List<ProductCategory>> fetchActive() {
    return ErrorMapper.guard(() async {
      final snapshot = await _categories
          .where('isActive', isEqualTo: true)
          .orderBy('sortOrder')
          .get();
      return snapshot.docs.map(ProductCategory.fromFirestore).toList();
    }, operation: 'load categories');
  }

  Future<ProductCategory?> fetch(String categoryId) {
    return ErrorMapper.guard(() async {
      final snapshot = await _categories.doc(categoryId).get();
      if (!snapshot.exists) return null;
      return ProductCategory.fromFirestore(snapshot);
    }, operation: 'load that category');
  }

  /// Looks up several categories by id, for showing category names on product cards.
  Future<Map<String, ProductCategory>> fetchByIds(Iterable<String> ids) async {
    final all = await fetchActive();
    final wanted = ids.toSet();
    return {
      for (final category in all)
        if (wanted.contains(category.id)) category.id: category,
    };
  }
}
