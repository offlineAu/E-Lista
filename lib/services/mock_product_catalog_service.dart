import 'product_catalog_service.dart';

/// A local stand-in for the external catalog.
///
/// It exists for two honest reasons: tests must not depend on a third-party service being
/// up, and the import flow has to be developable on a laptop with no internet. It is
/// **never** a silent fallback for the live service — when Open Food Facts fails at
/// runtime the app says the catalog is unavailable rather than quietly serving these rows,
/// because an owner importing a product needs to know whether the information came from a
/// real catalog or from a fixture.
///
/// Selected with `--dart-define=USE_MOCK_CATALOG=true`; the UI marks imported data as
/// development data whenever [isLive] is false.
class MockProductCatalogService implements ProductCatalogService {
  const MockProductCatalogService({
    this.latency = const Duration(milliseconds: 250),
  });

  /// Simulated network delay, so loading states are exercised during development.
  final Duration latency;

  @override
  String get displayName => 'Local sample catalog';

  @override
  bool get isLive => false;

  @override
  Future<CatalogProduct?> lookupByBarcode(String barcode) async {
    await Future<void>.delayed(latency);
    final code = barcode.trim();
    for (final product in _products) {
      if (product.barcode == code) return product;
    }
    return null;
  }

  @override
  Future<List<CatalogProduct>> search(String query, {int limit = 20}) async {
    await Future<void>.delayed(latency);
    final term = query.trim().toLowerCase();
    if (term.length < 2) return const [];

    return _products
        .where(
          (product) =>
              product.name.toLowerCase().contains(term) ||
              (product.brand?.toLowerCase().contains(term) ?? false) ||
              (product.category?.toLowerCase().contains(term) ?? false),
        )
        .take(limit)
        .toList();
  }

  /// A shelf's worth of products a Philippine sari-sari store actually carries.
  ///
  /// The barcodes are plausible EAN-13 values in the 480 (Philippines) prefix range but
  /// are **not** real registered codes — this is sample data, not a copy of a commercial
  /// database.
  static const List<CatalogProduct> _products = [
    CatalogProduct(
      barcode: '4800016641107',
      name: 'Piattos Cheese',
      brand: 'Jack n Jill',
      category: 'Snacks',
      description: 'Hexagon-shaped potato crisps, cheese flavour.',
      unit: '40 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800016641206',
      name: 'Nova Multigrain Snack',
      brand: 'Jack n Jill',
      category: 'Snacks',
      description: 'Multigrain crisps, country cheddar.',
      unit: '40 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4801981132096',
      name: 'Lucky Me Pancit Canton Original',
      brand: 'Lucky Me',
      category: 'Instant Noodles',
      description: 'Stir-fried instant noodles, original flavour.',
      unit: '60 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4801981132195',
      name: 'Lucky Me Beef na Beef Mami',
      brand: 'Lucky Me',
      category: 'Instant Noodles',
      description: 'Instant noodle soup, beef flavour.',
      unit: '55 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800024561107',
      name: 'Coca-Cola Sakto',
      brand: 'Coca-Cola',
      category: 'Beverages',
      description: 'Carbonated soft drink in a single-serve bottle.',
      unit: '295 mL',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800024561206',
      name: 'Sprite',
      brand: 'Coca-Cola',
      category: 'Beverages',
      description: 'Lemon-lime carbonated soft drink.',
      unit: '295 mL',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800361381109',
      name: 'Kopiko Brown Coffee 3-in-1',
      brand: 'Kopiko',
      category: 'Beverages',
      description: 'Instant coffee mix sachet.',
      unit: '25 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800194112093',
      name: 'Argentina Corned Beef',
      brand: 'Argentina',
      category: 'Canned Goods',
      description: 'Canned corned beef.',
      unit: '150 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800194112192',
      name: '555 Sardines in Tomato Sauce',
      brand: '555',
      category: 'Canned Goods',
      description: 'Canned sardines in tomato sauce.',
      unit: '155 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800888136107',
      name: 'Safeguard Pure White Soap',
      brand: 'Safeguard',
      category: 'Personal Care',
      description: 'Antibacterial bath soap bar.',
      unit: '130 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800888136206',
      name: 'Palmolive Shampoo Sachet',
      brand: 'Palmolive',
      category: 'Personal Care',
      description: 'Shampoo in a single-use sachet.',
      unit: '12 mL',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800361992091',
      name: 'Surf Powder Detergent',
      brand: 'Surf',
      category: 'Household',
      description: 'Powder laundry detergent sachet.',
      unit: '66 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800016200106',
      name: 'Sky Flakes Crackers',
      brand: 'M.Y. San',
      category: 'Snacks',
      description: 'Salted soda crackers.',
      unit: '25 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800047520105',
      name: 'Bear Brand Powdered Milk',
      brand: 'Bear Brand',
      category: 'Beverages',
      description: 'Powdered milk drink sachet.',
      unit: '33 g',
      source: 'Local sample catalog',
    ),
    CatalogProduct(
      barcode: '4800092770104',
      name: 'Datu Puti Soy Sauce',
      brand: 'Datu Puti',
      category: 'Condiments',
      description: 'Soy sauce in a resealable pouch.',
      unit: '200 mL',
      source: 'Local sample catalog',
    ),
  ];

  /// The sample rows, for tests that need to assert against known data.
  static List<CatalogProduct> get sampleProducts =>
      List.unmodifiable(_products);
}
