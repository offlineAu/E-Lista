import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../../models/price_history_entry.dart';
import '../../../models/product.dart';
import '../../../repositories/owner_product_repository.dart';

final ownerProductRepositoryProvider = Provider<OwnerProductRepository>((ref) {
  return OwnerProductRepository(ref.watch(firestoreProvider));
});

/// The whole catalog as the owner sees it, deactivated products included.
final ownerCatalogProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(ownerProductRepositoryProvider).watchAll();
});

/// A product together with its cost and pricing mode.
///
/// Read on demand rather than streamed with the list: the list shows a hundred products
/// and the cost of each one is a second document, so fetching them all would triple the
/// reads for information only the open product needs.
final ownerProductProvider = FutureProvider.autoDispose
    .family<OwnerProduct, String>((ref, productId) {
      return ref
          .watch(ownerProductRepositoryProvider)
          .requireOwnerProduct(productId);
    });

/// One product's cost, streamed so an edit screen follows a restock that changed it.
final productCostProvider = StreamProvider.autoDispose
    .family<ProductCost?, String>((ref, productId) {
      return ref.watch(ownerProductRepositoryProvider).watchCost(productId);
    });

/// One product's pricing audit trail.
final productPriceHistoryProvider = StreamProvider.autoDispose
    .family<List<PriceHistoryEntry>, String>((ref, productId) {
      return ref
          .watch(ownerProductRepositoryProvider)
          .watchPriceHistory(productId);
    });

/// The whole store's pricing trail.
final storePriceHistoryProvider = StreamProvider<List<PriceHistoryEntry>>((
  ref,
) {
  return ref.watch(ownerProductRepositoryProvider).watchAllPriceHistory();
});

/// The owner's product-list search box.
final ownerProductSearchProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

/// The catalog filtered by the search box, matched in memory.
///
/// The owner's list is already loaded and bounded, so filtering it locally is instant and
/// costs nothing — unlike the customer's search, which queries Firestore because the
/// catalog it searches was never fully loaded.
final filteredOwnerCatalogProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final catalog = ref.watch(ownerCatalogProvider);
  final query = ref.watch(ownerProductSearchProvider).trim().toLowerCase();

  return catalog.whenData((products) {
    if (query.isEmpty) return products;
    return products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          (product.brand?.toLowerCase().contains(query) ?? false) ||
          (product.barcode?.contains(query) ?? false);
    }).toList();
  });
});
