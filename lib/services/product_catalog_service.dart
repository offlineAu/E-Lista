import 'package:meta/meta.dart';

import '../core/errors/app_failure.dart';

/// A product as an external catalog describes it, normalised to E-Lista's shape.
///
/// This is **discovery information only**: a name, a brand, a picture. It carries no
/// price, no cost and no stock, and that omission is the point. An external catalog knows
/// what a pack of Piattos is; it does not know what this store paid for it, and treating a
/// catalog price as a cost would corrupt every profit figure downstream. The owner enters
/// the receipt cost, always.
@immutable
class CatalogProduct {
  const CatalogProduct({
    required this.barcode,
    required this.name,
    this.brand,
    this.category,
    this.description,
    this.imageUrl,
    this.unit,
    this.source = 'unknown',
  });

  final String barcode;
  final String name;
  final String? brand;

  /// The catalog's own category label, offered as a suggestion. The owner picks the shelf
  /// it actually goes on.
  final String? category;

  final String? description;
  final String? imageUrl;

  /// A pack size the catalog reported, e.g. `40 g`. Informational.
  final String? unit;

  /// Which catalog this came from, shown to the owner so they know what they are trusting.
  final String source;

  /// Whether there is enough here to be worth importing.
  bool get isUsable => barcode.trim().isNotEmpty && name.trim().isNotEmpty;

  @override
  String toString() => 'CatalogProduct($barcode, $name, $brand)';
}

/// Raised when the external catalog cannot be reached or has nothing useful.
///
/// Separate from a general failure so the UI can say the right thing: the store still
/// works, only *discovery* is unavailable, and manual entry is right there.
class CatalogUnavailable extends AppFailure {
  const CatalogUnavailable({
    super.message =
        'Product catalog service is temporarily unavailable. '
        'You can add this product manually.',
    super.cause,
    super.stackTrace,
  }) : super(severity: FailureSeverity.transient, code: 'catalog-unavailable');
}

/// Looks up product information from an external catalog.
///
/// This interface exists so the app is never welded to one provider. Open Food Facts is
/// the default because it needs no API key and covers a useful share of Philippine
/// barcodes; a store that outgrows it can be moved to a paid catalog by writing one more
/// implementation and changing one provider.
///
/// Two rules hold for every implementation:
///
/// * It is a **source of description, never of price.** Nothing here returns money.
/// * It is **optional to the running store.** Every method may fail, and the app must stay
///   fully usable when it does: existing products still display, sell and restock by
///   barcode. Only importing a product the store has never seen degrades, and the UI says
///   so plainly rather than pretending the lookup found nothing.
abstract interface class ProductCatalogService {
  /// A human-readable name for the catalog, shown when attributing imported data.
  String get displayName;

  /// Whether this implementation talks to a live service. `false` for the local mock, so
  /// the UI can be honest that it is showing development data.
  bool get isLive;

  /// Looks up one barcode. Returns `null` when the catalog simply does not have it —
  /// which is a normal outcome, not an error.
  ///
  /// Throws [CatalogUnavailable] when the catalog could not be asked at all.
  Future<CatalogProduct?> lookupByBarcode(String barcode);

  /// Searches by name or brand. Returns an empty list when nothing matches.
  ///
  /// Throws [CatalogUnavailable] when the catalog could not be asked at all.
  Future<List<CatalogProduct>> search(String query, {int limit = 20});
}
