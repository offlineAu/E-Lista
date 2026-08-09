import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

/// A product category, e.g. Snacks, Beverages, Canned Goods, Household.
///
/// Categories live in `categories/{id}` and are world-readable. They exist mainly to give
/// the customer a way to browse without typing, so the ordering the owner chooses matters
/// more than any hierarchy — there are no sub-categories on purpose.
@immutable
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.iconName,
    this.sortOrder = 0,
    this.isActive = true,
    this.productCount,
  });

  final String id;
  final String name;

  /// Material icon name, resolved by `CategoryIcons` so Firestore stores a stable string
  /// rather than a Flutter-specific code point.
  final String? iconName;

  /// Ascending display order. Ties fall back to name.
  final int sortOrder;

  final bool isActive;

  /// Maintained by the server when products change; `null` when it has never been
  /// computed, which the UI shows as no count rather than as zero.
  final int? productCount;

  ProductCategory copyWith({
    String? name,
    String? iconName,
    int? sortOrder,
    bool? isActive,
    int? productCount,
  }) {
    return ProductCategory(
      id: id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      productCount: productCount ?? this.productCount,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'nameLower': name.toLowerCase(),
    'iconName': iconName,
    'sortOrder': sortOrder,
    'isActive': isActive,
    'productCount': productCount,
  };

  static ProductCategory fromFirestore(
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) => ProductCategory.fromJson(snapshot.id, snapshot.data() ?? const {});

  static ProductCategory fromJson(String id, Map<String, Object?> json) {
    return ProductCategory(
      id: id,
      name: (json['name'] as String?) ?? 'Uncategorised',
      iconName: json['iconName'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isActive: (json['isActive'] as bool?) ?? true,
      productCount: (json['productCount'] as num?)?.toInt(),
    );
  }

  /// The categories a new store starts with — the shelves of an actual sari-sari store.
  ///
  /// Seeded once on first run; the owner renames, reorders and adds to them afterwards.
  static const List<ProductCategory> defaults = [
    ProductCategory(
      id: 'snacks',
      name: 'Snacks',
      iconName: 'cookie',
      sortOrder: 10,
    ),
    ProductCategory(
      id: 'beverages',
      name: 'Beverages',
      iconName: 'local_drink',
      sortOrder: 20,
    ),
    ProductCategory(
      id: 'instant-noodles',
      name: 'Instant Noodles',
      iconName: 'ramen_dining',
      sortOrder: 30,
    ),
    ProductCategory(
      id: 'canned-goods',
      name: 'Canned Goods',
      iconName: 'inventory_2',
      sortOrder: 40,
    ),
    ProductCategory(
      id: 'rice-grains',
      name: 'Rice & Grains',
      iconName: 'rice_bowl',
      sortOrder: 50,
    ),
    ProductCategory(
      id: 'condiments',
      name: 'Condiments',
      iconName: 'soup_kitchen',
      sortOrder: 60,
    ),
    ProductCategory(
      id: 'household',
      name: 'Household',
      iconName: 'cleaning_services',
      sortOrder: 70,
    ),
    ProductCategory(
      id: 'personal-care',
      name: 'Personal Care',
      iconName: 'soap',
      sortOrder: 80,
    ),
    ProductCategory(
      id: 'school-office',
      name: 'School & Office',
      iconName: 'edit',
      sortOrder: 90,
    ),
    ProductCategory(
      id: 'others',
      name: 'Others',
      iconName: 'category',
      sortOrder: 999,
    ),
  ];

  @override
  bool operator ==(Object other) => other is ProductCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ProductCategory($id, $name)';
}
