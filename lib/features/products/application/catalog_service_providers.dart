import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../services/mock_product_catalog_service.dart';
import '../../../services/open_food_facts_catalog_service.dart';
import '../../../services/product_catalog_service.dart';

/// The external product catalog.
///
/// Which implementation is used is a build-time choice, not a runtime fallback: passing
/// `--dart-define=USE_MOCK_CATALOG=true` selects the local sample data, and everything
/// else uses the live service. When the live service fails, the app reports it as
/// unavailable — it never silently substitutes the mock, because an owner importing a
/// product needs to know whether what they are looking at came from a real catalog.
final productCatalogServiceProvider = Provider<ProductCatalogService>((ref) {
  if (AppConfig.useMockCatalog) {
    return const MockProductCatalogService();
  }

  final service = OpenFoodFactsCatalogService();
  ref.onDispose(service.dispose);
  return service;
});

/// Barcode lookup against the external catalog.
///
/// `null` means the catalog does not have this barcode — a normal answer that leads to
/// manual entry. A thrown [CatalogUnavailable] means the catalog could not be reached,
/// which the UI distinguishes because the two need different words and different buttons.
final catalogBarcodeLookupProvider = FutureProvider.autoDispose
    .family<CatalogProduct?, String>((ref, barcode) async {
      return ref.watch(productCatalogServiceProvider).lookupByBarcode(barcode);
    });

/// Free-text search against the external catalog, for importing a product the store has
/// never carried.
final catalogSearchProvider = FutureProvider.autoDispose
    .family<List<CatalogProduct>, String>((ref, query) async {
      if (query.trim().length < 2) return const [];
      return ref.watch(productCatalogServiceProvider).search(query);
    });
