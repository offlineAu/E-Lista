import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../core/money/money.dart';
import '../core/money/percentage.dart';
import '../features/pricing/domain/pricing_engine.dart';

/// Where a product's descriptive information originally came from.
enum ProductSource {
  /// Typed in by the owner.
  manual,

  /// Imported from the external product catalog and then priced by the owner.
  catalogImport;

  static ProductSource fromJson(Object? value) => switch (value) {
    'catalogImport' => ProductSource.catalogImport,
    _ => ProductSource.manual,
  };

  String toJson() => name;

  String get label => switch (this) {
    ProductSource.manual => 'Added manually',
    ProductSource.catalogImport => 'Imported from catalog',
  };
}

/// A product as a **customer** may see it.
///
/// This maps to `products/{id}`, which is world-readable. It deliberately contains no cost
/// price, profit percentage or pricing mode: those live in `products/{id}/private/pricing`
/// as a [ProductCost], because Firestore rules grant access per document and a single
/// document holding both could not be shown to customers safely.
@immutable
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.cashPrice,
    required this.gcashBasePrice,
    required this.stockQuantity,
    required this.lowStockThreshold,
    required this.unit,
    required this.isActive,
    this.barcode,
    this.brand,
    this.categoryId,
    this.description,
    this.imageUrl,
    this.source = ProductSource.manual,
    this.searchTokens = const [],
    this.unitsSoldTotal = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// EAN-13/UPC-A as printed on the pack. Absent for repacked goods sold by scoop.
  final String? barcode;

  final String name;
  final String? brand;
  final String? categoryId;
  final String? description;
  final String? imageUrl;

  /// Price a cash customer pays per unit. Always whole pesos.
  final Money cashPrice;

  /// Price a GCash customer pays per unit, before the once-per-transaction convenience
  /// fee. Keeps centavos.
  final Money gcashBasePrice;

  final int stockQuantity;

  /// At or below this, the product is low on stock and appears on the owner dashboard.
  final int lowStockThreshold;

  /// How the product is sold: `pc`, `pack`, `sachet`, `bottle`, `kg`.
  final String unit;

  /// Deactivated products stay in Firestore so old orders keep their names and prices,
  /// but they are hidden from the customer catalog and cannot be added to a cart.
  final bool isActive;

  final ProductSource source;

  /// Lowercased prefixes of the name, brand and unit, used for the catalog search query.
  /// Maintained by [buildSearchTokens]; not meant to be read by the UI.
  final List<String> searchTokens;

  /// Lifetime units sold, maintained server-side as sales are rung up. Not net of any later
  /// cancellation — a popularity signal for the storefront, not an inventory figure.
  final int unitsSoldTotal;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether stock has fallen to the threshold the owner set.
  bool get isLowStock => stockQuantity <= lowStockThreshold;

  /// Whether the product can be added to a cart at all.
  bool get isOutOfStock => stockQuantity <= 0;

  /// Whether a customer may buy this right now.
  bool get isPurchasable => isActive && !isOutOfStock;

  /// The most a customer may put in their cart.
  int get maximumOrderQuantity => stockQuantity < 0 ? 0 : stockQuantity;

  Product copyWith({
    String? id,
    Object? barcode = _unset,
    String? name,
    Object? brand = _unset,
    Object? categoryId = _unset,
    Object? description = _unset,
    Object? imageUrl = _unset,
    Money? cashPrice,
    Money? gcashBasePrice,
    int? stockQuantity,
    int? lowStockThreshold,
    String? unit,
    bool? isActive,
    ProductSource? source,
    List<String>? searchTokens,
    int? unitsSoldTotal,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      barcode: identical(barcode, _unset) ? this.barcode : barcode as String?,
      name: name ?? this.name,
      brand: identical(brand, _unset) ? this.brand : brand as String?,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      description: identical(description, _unset)
          ? this.description
          : description as String?,
      imageUrl: identical(imageUrl, _unset)
          ? this.imageUrl
          : imageUrl as String?,
      cashPrice: cashPrice ?? this.cashPrice,
      gcashBasePrice: gcashBasePrice ?? this.gcashBasePrice,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      unit: unit ?? this.unit,
      isActive: isActive ?? this.isActive,
      source: source ?? this.source,
      searchTokens: searchTokens ?? this.searchTokens,
      unitsSoldTotal: unitsSoldTotal ?? this.unitsSoldTotal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'barcode': barcode,
    'name': name,
    'nameLower': name.toLowerCase(),
    'brand': brand,
    'categoryId': categoryId,
    'description': description,
    'imageUrl': imageUrl,
    'cashPriceCentavos': cashPrice.centavos,
    'gcashBasePriceCentavos': gcashBasePrice.centavos,
    'stockQuantity': stockQuantity,
    'lowStockThreshold': lowStockThreshold,
    // Firestore cannot compare two fields in a query, so the comparison is
    // materialised here and rewritten in the same transaction as every stock change.
    // That is what lets the dashboard ask for low-stock products directly.
    'isLowStock': stockQuantity <= lowStockThreshold,
    'unit': unit,
    'isActive': isActive,
    'source': source.toJson(),
    'searchTokens': searchTokens,
    'unitsSoldTotal': unitsSoldTotal,
    'createdAt': createdAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(createdAt!),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Product fromFirestore(
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, Object?>{};
    return Product.fromJson(snapshot.id, data);
  }

  static Product fromJson(String id, Map<String, Object?> json) {
    return Product(
      id: id,
      barcode: json['barcode'] as String?,
      name: (json['name'] as String?) ?? 'Unnamed product',
      brand: json['brand'] as String?,
      categoryId: json['categoryId'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      cashPrice: Money.fromJson(json['cashPriceCentavos']),
      gcashBasePrice: Money.fromJson(json['gcashBasePriceCentavos']),
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 0,
      unit: (json['unit'] as String?) ?? 'pc',
      isActive: (json['isActive'] as bool?) ?? true,
      source: ProductSource.fromJson(json['source']),
      searchTokens:
          (json['searchTokens'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      unitsSoldTotal: (json['unitsSoldTotal'] as num?)?.toInt() ?? 0,
      createdAt: _readTimestamp(json['createdAt']),
      updatedAt: _readTimestamp(json['updatedAt']),
    );
  }

  /// Builds the token list backing catalog search.
  ///
  /// Firestore has no full-text search. Storing every prefix of every word in the name,
  /// brand and category lets a single `array-contains` query answer "Piat", "piatt" and
  /// "cheese" without a third-party search service. Tokens are lowercased and
  /// accent-stripped so "Café" matches "cafe".
  ///
  /// The list is bounded: a five-word name of ten letters per word yields at most fifty
  /// tokens, far below Firestore's 40 000-element array-index limit.
  static List<String> buildSearchTokens({
    required String name,
    String? brand,
    String? categoryName,
    String? barcode,
  }) {
    final tokens = <String>{};

    for (final field in [name, brand, categoryName]) {
      if (field == null || field.trim().isEmpty) continue;
      for (final word in normaliseForSearch(field).split(' ')) {
        if (word.length < 2) continue;
        for (var length = 2; length <= word.length; length++) {
          tokens.add(word.substring(0, length));
        }
      }
    }

    // The full barcode is matched exactly by a separate equality query, but the trailing
    // digits are what a person reads off a pack, so the last few are searchable too.
    if (barcode != null && barcode.length >= 4) {
      tokens.add(barcode);
      tokens.add(barcode.substring(barcode.length - 4));
    }

    return tokens.toList()..sort();
  }

  /// Lowercases, strips accents and collapses punctuation to spaces.
  static String normaliseForSearch(String input) {
    final lowered = input.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lowered.runes) {
      final character = String.fromCharCode(rune);
      final replacement = _accentFolding[character];
      buffer.write(replacement ?? character);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const Map<String, String> _accentFolding = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ñ': 'n',
    'ç': 'c',
  };

  static DateTime? _readTimestamp(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    DateTime() => value,
    int() => DateTime.fromMillisecondsSinceEpoch(value),
    _ => null,
  };

  @override
  bool operator ==(Object other) => other is Product && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Product($id, $name, cash: $cashPrice, stock: $stockQuantity)';

  static const Object _unset = Object();
}

/// The owner-only half of a product: what it cost and how it is priced.
///
/// Stored at `products/{id}/private/pricing`, readable only by the owner. Keeping it in a
/// separate document is what makes "customers cannot read cost price" enforceable by
/// security rules rather than by hoping the client does not ask for the field.
@immutable
class ProductCost {
  const ProductCost({
    required this.productId,
    required this.costPrice,
    required this.pricingMode,
    this.profitPercentage,
    this.updatedAt,
    this.updatedBy,
  });

  final String productId;

  /// What the owner actually paid, from the receipt. Never taken from the external
  /// catalog — that is a discovery source, not a price list.
  final Money costPrice;

  final PricingMode pricingMode;

  /// Set only when [pricingMode] is [PricingMode.custom]; otherwise the store-wide default
  /// applies.
  final Percentage? profitPercentage;

  final DateTime? updatedAt;
  final String? updatedBy;

  /// The percentage this product actually prices itself with, given the store default.
  Percentage effectivePercentage(Percentage storeDefault) =>
      PricingEngine.effectiveProfitPercentage(
        mode: pricingMode,
        productPercentage: profitPercentage,
        storeDefault: storeDefault,
      );

  /// The prices this product should be selling at, given the store default.
  ///
  /// Used by the owner's edit screen to preview prices live, and by the server to
  /// recompute them when the cost or the store default changes.
  ProductPrices pricesGiven(Percentage storeDefault) => PricingEngine.pricesFor(
    cost: costPrice,
    profitPercentage: effectivePercentage(storeDefault),
  );

  ProductCost copyWith({
    Money? costPrice,
    PricingMode? pricingMode,
    Object? profitPercentage = _unset,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return ProductCost(
      productId: productId,
      costPrice: costPrice ?? this.costPrice,
      pricingMode: pricingMode ?? this.pricingMode,
      profitPercentage: identical(profitPercentage, _unset)
          ? this.profitPercentage
          : profitPercentage as Percentage?,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  Map<String, Object?> toJson() => {
    'costPriceCentavos': costPrice.centavos,
    'pricingMode': pricingMode.toJson(),
    'profitPercentageBasisPoints': profitPercentage?.basisPoints,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': updatedBy,
  };

  static ProductCost fromJson(String productId, Map<String, Object?> json) {
    final rawPercentage = json['profitPercentageBasisPoints'];
    return ProductCost(
      productId: productId,
      costPrice: Money.fromJson(json['costPriceCentavos']),
      pricingMode: PricingMode.fromJson(json['pricingMode']),
      profitPercentage: rawPercentage == null
          ? null
          : Percentage.fromJson(rawPercentage),
      updatedAt: Product._readTimestamp(json['updatedAt']),
      updatedBy: json['updatedBy'] as String?,
    );
  }

  @override
  String toString() =>
      'ProductCost($productId, cost: $costPrice, ${pricingMode.name})';

  static const Object _unset = Object();
}

/// A product together with its owner-only pricing information.
///
/// Only ever constructed on owner screens, where both documents have been read.
@immutable
class OwnerProduct {
  const OwnerProduct({required this.product, required this.cost});

  final Product product;
  final ProductCost cost;

  String get id => product.id;

  /// Profit on one unit sold for cash.
  Money get cashProfitPerUnit => product.cashPrice - cost.costPrice;

  /// Profit on one unit sold via GCash, before the transaction's convenience fee.
  Money get gcashProfitPerUnit => product.gcashBasePrice - cost.costPrice;

  /// What the stock on hand cost to acquire.
  Money get inventoryValueAtCost => cost.costPrice * product.stockQuantity;
}
