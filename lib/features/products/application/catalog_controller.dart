import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../repositories/product_repository.dart';

/// What the catalog list is showing right now.
///
/// Loading and error are separate from the product list rather than replacing it, so
/// paging to the next page does not blank out the page the shopper is reading, and a
/// failure while paging leaves what they already have on screen.
@immutable
class CatalogState {
  const CatalogState({
    this.products = const [],
    this.categoryId,
    this.isLoadingFirstPage = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.failure,
  });

  final List<Product> products;

  /// The category filter, or `null` for everything.
  final String? categoryId;

  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;

  /// The last failure, kept so the list can show it without discarding the products.
  final AppFailure? failure;

  bool get isEmpty =>
      products.isEmpty && !isLoadingFirstPage && failure == null;

  CatalogState copyWith({
    List<Product>? products,
    Object? categoryId = _unset,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    Object? failure = _unset,
  }) {
    return CatalogState(
      products: products ?? this.products,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as AppFailure?,
    );
  }

  static const Object _unset = Object();
}

/// Pages through the customer catalog.
///
/// Paging rather than a single unbounded query is deliberate. `collection('products')`
/// with no limit works for the forty products a store starts with and becomes both a bill
/// and a jank source at four thousand — and it is not a problem that shows up in testing,
/// only in a real store two years in.
class CatalogController extends StateNotifier<CatalogState> {
  CatalogController(this._products, {String? categoryId})
    : super(CatalogState(categoryId: categoryId)) {
    loadFirstPage();
  }

  final ProductRepository _products;

  DocumentSnapshot<Map<String, Object?>>? _cursor;

  Future<void> loadFirstPage() async {
    if (state.isLoadingFirstPage) return;

    _cursor = null;
    state = state.copyWith(
      isLoadingFirstPage: true,
      failure: null,
      hasMore: true,
    );

    try {
      final page = await _products.fetchCatalogPage(
        categoryId: state.categoryId,
      );
      if (!mounted) return;
      _cursor = page.lastDocument;
      state = state.copyWith(
        products: page.products,
        hasMore: page.hasMore,
        isLoadingFirstPage: false,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingFirstPage: false,
        failure: _asFailure(error, stackTrace),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoadingFirstPage || !state.hasMore) {
      return;
    }
    if (_cursor == null) return;

    state = state.copyWith(isLoadingMore: true, failure: null);

    try {
      final page = await _products.fetchCatalogPage(
        categoryId: state.categoryId,
        startAfter: _cursor,
      );
      if (!mounted) return;
      _cursor = page.lastDocument ?? _cursor;
      state = state.copyWith(
        products: [...state.products, ...page.products],
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        failure: _asFailure(error, stackTrace),
      );
    }
  }

  /// Reloads from the top — pull to refresh, and Retry after a failure.
  ///
  /// Changing the category filter does not go through here: the provider is keyed on the
  /// selected category, so selecting a different one builds a fresh controller.
  Future<void> refresh() => loadFirstPage();

  static AppFailure _asFailure(Object error, StackTrace stackTrace) {
    return error is AppFailure
        ? error
        : ErrorMapper.map(error, stackTrace, operation: 'load products');
  }
}

/// The catalog for the home screen, filtered by the selected category.
final catalogControllerProvider =
    StateNotifierProvider.autoDispose<CatalogController, CatalogState>((ref) {
      final categoryId = ref.watch(selectedCategoryProvider);
      // Keeps the fetched page alive for a moment after the screen leaves, so tapping a
      // product and coming straight back does not re-read the whole page.
      final link = ref.keepAlive();
      ref.onDispose(link.close);

      return CatalogController(
        ref.watch(productRepositoryProvider),
        categoryId: categoryId,
      );
    });

/// The category chip the shopper has selected, or `null` for "All".
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

/// The store's categories, for the chip row and the categories screen.
final categoriesProvider = StreamProvider<List<ProductCategory>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchActive();
});
