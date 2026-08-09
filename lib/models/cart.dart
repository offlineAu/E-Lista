import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../core/money/money.dart';
import '../features/pricing/domain/gcash_fee_schedule.dart';
import 'payment_method.dart';
import 'product.dart';

/// One product in the cart.
///
/// The prices held here are a **preview**, refreshed from the catalog whenever the cart is
/// shown. They are never what the customer is charged: `placeOrder` re-reads every product
/// server-side and charges the price it finds there. If the two disagree, checkout stops
/// and tells the customer the price changed rather than quietly billing either figure.
@immutable
class CartItem {
  const CartItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.cashPrice,
    required this.gcashPrice,
    required this.availableStock,
    required this.isActive,
    this.brand,
    this.unit = 'pc',
    this.imageUrl,
    this.addedAt,
  });

  final String productId;
  final String productName;
  final String? brand;
  final String unit;
  final String? imageUrl;

  final int quantity;

  /// Last-seen prices, for showing a running total before checkout.
  final Money cashPrice;
  final Money gcashPrice;

  /// Last-seen stock, used to cap the quantity stepper.
  final int availableStock;

  /// Whether the product was still on sale when the cart was last refreshed.
  final bool isActive;

  final DateTime? addedAt;

  /// The line total under [method], for the cart preview.
  Money lineTotal(PaymentMethod method) => unitPrice(method) * quantity;

  Money unitPrice(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => cashPrice,
    PaymentMethod.gcash => gcashPrice,
  };

  /// True when this line cannot be ordered as it stands.
  bool get hasProblem =>
      !isActive || availableStock <= 0 || quantity > availableStock;

  /// What to tell the customer about the problem, or `null` when the line is fine.
  String? get problemMessage {
    if (!isActive) return 'No longer available';
    if (availableStock <= 0) return 'Out of stock';
    if (quantity > availableStock) {
      return 'Only $availableStock left — reduce the quantity';
    }
    return null;
  }

  CartItem copyWith({
    int? quantity,
    Money? cashPrice,
    Money? gcashPrice,
    int? availableStock,
    bool? isActive,
    String? productName,
    Object? brand = _unset,
    String? unit,
    Object? imageUrl = _unset,
  }) {
    return CartItem(
      productId: productId,
      productName: productName ?? this.productName,
      brand: identical(brand, _unset) ? this.brand : brand as String?,
      unit: unit ?? this.unit,
      imageUrl: identical(imageUrl, _unset)
          ? this.imageUrl
          : imageUrl as String?,
      quantity: quantity ?? this.quantity,
      cashPrice: cashPrice ?? this.cashPrice,
      gcashPrice: gcashPrice ?? this.gcashPrice,
      availableStock: availableStock ?? this.availableStock,
      isActive: isActive ?? this.isActive,
      addedAt: addedAt,
    );
  }

  /// Refreshes the snapshot fields from a freshly read product, keeping the quantity the
  /// customer chose (capped at what is actually left).
  CartItem refreshedFrom(Product product) {
    final cappedQuantity = product.stockQuantity <= 0
        ? quantity
        : quantity.clamp(1, product.stockQuantity);
    return copyWith(
      productName: product.name,
      brand: product.brand,
      unit: product.unit,
      imageUrl: product.imageUrl,
      quantity: cappedQuantity,
      cashPrice: product.cashPrice,
      gcashPrice: product.gcashBasePrice,
      availableStock: product.stockQuantity,
      isActive: product.isActive,
    );
  }

  static CartItem fromProduct(Product product, {int quantity = 1}) => CartItem(
    productId: product.id,
    productName: product.name,
    brand: product.brand,
    unit: product.unit,
    imageUrl: product.imageUrl,
    quantity: quantity,
    cashPrice: product.cashPrice,
    gcashPrice: product.gcashBasePrice,
    availableStock: product.stockQuantity,
    isActive: product.isActive,
    addedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'brand': brand,
    'unit': unit,
    'imageUrl': imageUrl,
    'quantity': quantity,
    'cashPriceCentavos': cashPrice.centavos,
    'gcashPriceCentavos': gcashPrice.centavos,
    'availableStock': availableStock,
    'isActive': isActive,
    'addedAt': addedAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(addedAt!),
  };

  static CartItem fromJson(Map<String, Object?> json) => CartItem(
    productId: (json['productId'] as String?) ?? '',
    productName: (json['productName'] as String?) ?? 'Product',
    brand: json['brand'] as String?,
    unit: (json['unit'] as String?) ?? 'pc',
    imageUrl: json['imageUrl'] as String?,
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    cashPrice: Money.fromJson(json['cashPriceCentavos']),
    gcashPrice: Money.fromJson(json['gcashPriceCentavos']),
    availableStock: (json['availableStock'] as num?)?.toInt() ?? 0,
    isActive: (json['isActive'] as bool?) ?? true,
    addedAt: switch (json['addedAt']) {
      Timestamp() => (json['addedAt']! as Timestamp).toDate(),
      _ => null,
    },
  );

  @override
  bool operator ==(Object other) =>
      other is CartItem &&
      other.productId == productId &&
      other.quantity == quantity &&
      other.cashPrice == cashPrice &&
      other.gcashPrice == gcashPrice;

  @override
  int get hashCode => Object.hash(productId, quantity, cashPrice, gcashPrice);

  @override
  String toString() => 'CartItem($productName ×$quantity)';

  static const Object _unset = Object();
}

/// The customer's basket.
///
/// Stored at `carts/{uid}`, which every signed-in user has — including guests, who are
/// signed in anonymously. That is why a guest's cart survives closing the app and why it
/// carries over unchanged when they later create an account: the uid does not change.
@immutable
class Cart {
  const Cart({required this.items, this.updatedAt});

  static const Cart empty = Cart(items: []);

  final List<CartItem> items;
  final DateTime? updatedAt;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  /// Total number of units, for the badge on the cart tab.
  int get itemCount =>
      items.fold(0, (running, item) => running + item.quantity);

  int get lineCount => items.length;

  /// Lines that cannot be ordered as they stand.
  List<CartItem> get problemItems =>
      items.where((item) => item.hasProblem).toList();

  bool get canCheckout => isNotEmpty && problemItems.isEmpty;

  /// Preview subtotal under [method], before any convenience fee.
  Money subtotal(PaymentMethod method) =>
      Money.sum(items.map((item) => item.lineTotal(method)));

  /// Preview convenience fee: one fee for the whole basket, ₱0 unless the method charges
  /// one.
  ///
  /// An empty basket carries no fee. The lowest tier starts at ₱0, so asking the schedule
  /// would return the small-order fee for a cart with nothing in it — a number no customer
  /// should ever be shown, and one no order could ever charge, since an empty order is
  /// refused outright.
  Money convenienceFee(PaymentMethod method, GcashFeeSchedule schedule) {
    if (isEmpty || !method.chargesConvenienceFee) return Money.zero;
    return schedule.feeFor(subtotal(method));
  }

  /// Preview total under [method].
  Money total(PaymentMethod method, GcashFeeSchedule schedule) =>
      subtotal(method) + convenienceFee(method, schedule);

  CartItem? findItem(String productId) {
    for (final item in items) {
      if (item.productId == productId) return item;
    }
    return null;
  }

  int quantityOf(String productId) => findItem(productId)?.quantity ?? 0;

  /// Adds [quantity] of [product], merging with an existing line and never exceeding the
  /// stock last seen.
  Cart addProduct(Product product, {int quantity = 1}) {
    final existing = findItem(product.id);
    final cap = product.stockQuantity;

    if (existing == null) {
      final capped = cap <= 0 ? quantity : quantity.clamp(1, cap);
      return Cart(
        items: [
          ...items,
          CartItem.fromProduct(product, quantity: capped),
        ],
        updatedAt: DateTime.now(),
      );
    }

    final merged = existing.quantity + quantity;
    final capped = cap <= 0 ? merged : merged.clamp(1, cap);
    return updateQuantity(product.id, capped);
  }

  /// Sets the quantity of a line; a quantity of zero or less removes it.
  Cart updateQuantity(String productId, int quantity) {
    if (quantity <= 0) return removeProduct(productId);
    return Cart(
      items: [
        for (final item in items)
          if (item.productId == productId)
            item.copyWith(quantity: quantity)
          else
            item,
      ],
      updatedAt: DateTime.now(),
    );
  }

  Cart removeProduct(String productId) => Cart(
    items: items.where((item) => item.productId != productId).toList(),
    updatedAt: DateTime.now(),
  );

  Cart clear() => Cart(items: const [], updatedAt: DateTime.now());

  /// Re-reads prices and stock from the current catalog, dropping lines whose product has
  /// disappeared entirely.
  Cart refreshedFrom(Map<String, Product> productsById) {
    final refreshed = <CartItem>[];
    for (final item in items) {
      final product = productsById[item.productId];
      if (product == null) continue;
      refreshed.add(item.refreshedFrom(product));
    }
    return Cart(items: refreshed, updatedAt: DateTime.now());
  }

  Map<String, Object?> toJson() => {
    'items': items.map((item) => item.toJson()).toList(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Cart fromJson(Map<String, Object?>? json) {
    if (json == null) return Cart.empty;
    return Cart(
      items: (json['items'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((raw) => CartItem.fromJson(raw.cast<String, Object?>()))
          .toList(),
      updatedAt: switch (json['updatedAt']) {
        Timestamp() => (json['updatedAt']! as Timestamp).toDate(),
        _ => null,
      },
    );
  }

  @override
  String toString() => 'Cart($lineCount lines, $itemCount items)';
}
