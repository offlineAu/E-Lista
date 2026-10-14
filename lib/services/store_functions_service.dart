import 'package:cloud_functions/cloud_functions.dart';

import '../core/config/app_config.dart';
import '../core/errors/error_mapper.dart';
import '../core/money/money.dart';
import '../core/money/percentage.dart';
import '../features/owner/domain/pos_ticket.dart';
import '../features/pricing/domain/gcash_fee_schedule.dart';
import '../features/pricing/domain/pricing_engine.dart';
import '../models/cart.dart';
import '../models/inventory_transaction.dart';
import '../models/order.dart';
import '../models/payment_method.dart';

/// What the server decided an order costs.
///
/// Returned by [StoreFunctionsService.placeOrder]. These figures, not the client's
/// preview, are what the customer pays and what the confirmation screen shows.
class PlacedOrder {
  const PlacedOrder({
    required this.orderId,
    required this.orderNumber,
    required this.subtotal,
    required this.convenienceFee,
    required this.total,
  });

  final String orderId;
  final String orderNumber;
  final Money subtotal;
  final Money convenienceFee;
  final Money total;

  static PlacedOrder fromJson(Map<String, Object?> json) => PlacedOrder(
    orderId: (json['orderId'] as String?) ?? '',
    orderNumber: (json['orderNumber'] as String?) ?? '',
    subtotal: Money.fromJson(json['subtotalCentavos']),
    convenienceFee: Money.fromJson(json['convenienceFeeCentavos']),
    total: Money.fromJson(json['totalCentavos']),
  );
}

/// What the server booked for a cashier's walk-in sale.
///
/// Returned by [StoreFunctionsService.placeWalkInSale]. [amountTendered]/[changeDue] are
/// `null` for GCash — see [StoreOrder.amountTendered] for why that is not `total`/zero.
class PlacedWalkInSale {
  const PlacedWalkInSale({
    required this.orderId,
    required this.orderNumber,
    required this.subtotal,
    required this.convenienceFee,
    required this.total,
    required this.paymentMethod,
    this.amountTendered,
    this.changeDue,
  });

  final String orderId;
  final String orderNumber;
  final Money subtotal;
  final Money convenienceFee;
  final Money total;
  final PaymentMethod paymentMethod;
  final Money? amountTendered;
  final Money? changeDue;

  static PlacedWalkInSale fromJson(
    Map<String, Object?> json,
    PaymentMethod paymentMethod,
  ) => PlacedWalkInSale(
    orderId: (json['orderId'] as String?) ?? '',
    orderNumber: (json['orderNumber'] as String?) ?? '',
    subtotal: Money.fromJson(json['subtotalCentavos']),
    convenienceFee: Money.fromJson(json['convenienceFeeCentavos']),
    total: Money.fromJson(json['totalCentavos']),
    paymentMethod: paymentMethod,
    amountTendered: json['amountTenderedCentavos'] == null
        ? null
        : Money.fromJson(json['amountTenderedCentavos']),
    changeDue: json['changeCentavos'] == null
        ? null
        : Money.fromJson(json['changeCentavos']),
  );
}

/// What the server recorded for an end-of-shift cash count.
class RecordedCashCount {
  const RecordedCashCount({
    required this.expected,
    required this.counted,
    required this.difference,
  });

  final Money expected;
  final Money counted;

  /// `counted - expected`. Positive means the drawer had more than expected, negative
  /// means it came up short.
  final Money difference;

  static RecordedCashCount fromJson(Map<String, Object?> json) =>
      RecordedCashCount(
        expected: Money.fromJson(json['expectedCentavos']),
        counted: Money.fromJson(json['countedCentavos']),
        difference: Money.fromJson(json['differenceCentavos']),
      );
}

/// The prices the server derived after saving a product.
class SavedProduct {
  const SavedProduct({
    required this.productId,
    required this.cashPrice,
    required this.gcashBasePrice,
    required this.profitPercentage,
  });

  final String productId;
  final Money cashPrice;
  final Money gcashBasePrice;
  final Percentage profitPercentage;

  static SavedProduct fromJson(Map<String, Object?> json) => SavedProduct(
    productId: (json['productId'] as String?) ?? '',
    cashPrice: Money.fromJson(json['cashPriceCentavos']),
    gcashBasePrice: Money.fromJson(json['gcashBasePriceCentavos']),
    profitPercentage: Percentage.fromJson(json['profitBasisPoints']),
  );
}

/// The stock levels either side of an inventory movement.
class InventoryChange {
  const InventoryChange({
    required this.productId,
    required this.previousStock,
    required this.newStock,
  });

  final String productId;
  final int previousStock;
  final int newStock;

  int get delta => newStock - previousStock;

  static InventoryChange fromJson(Map<String, Object?> json) => InventoryChange(
    productId: (json['productId'] as String?) ?? '',
    previousStock: (json['previousStock'] as num?)?.toInt() ?? 0,
    newStock: (json['newStock'] as num?)?.toInt() ?? 0,
  );
}

/// Calls the Cloud Functions that own the store's write path.
///
/// Everything financial goes through here rather than through a Firestore write, because
/// the client is not trusted with it: prices, stock, order totals, fees and sales are all
/// derived server-side from what is actually in the database.
///
/// The client still computes a preview of the same numbers so a shopper sees a total
/// before the round trip. When the two disagree — a price changed mid-checkout — the
/// server refuses the order and says so, rather than charging either figure.
class StoreFunctionsService {
  StoreFunctionsService(this._functions);

  final FirebaseFunctions _functions;

  HttpsCallable _callable(String name, {Duration? timeout}) {
    return _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(
        timeout: timeout ?? AppConfig.backendTimeout,
      ),
    );
  }

  /// Places an order from the cart.
  ///
  /// [expectedTotal] is the figure the customer was shown. The server compares it with
  /// what it computes and refuses the order if they differ, so nobody is ever charged a
  /// number they did not see.
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required PaymentMethod paymentMethod,
    required OrderContact contact,
    Money? expectedTotal,
  }) {
    return ErrorMapper.guard(() async {
      final response = await _callable('placeOrder').call<Object?>({
        'items': [
          for (final item in cart.items)
            {'productId': item.productId, 'quantity': item.quantity},
        ],
        'paymentMethod': paymentMethod.id,
        'contactName': contact.name,
        'contactPhone': contact.phoneNumber,
        'contactAddress': contact.address,
        'contactNotes': contact.notes,
        if (expectedTotal != null)
          'expectedTotalCentavos': expectedTotal.centavos,
      });
      return PlacedOrder.fromJson(_asMap(response.data));
    }, operation: 'place your order');
  }

  /// Rings up a walk-in sale at the register. Owner or cashier.
  ///
  /// Unlike [placeOrder], this books straight to [OrderStatus.completed] — a sale at the
  /// counter has already happened by the time this is called, so there is no pending state
  /// to walk through. [amountTendered] is required for cash and ignored for GCash, which is
  /// exact by construction; the server (never this client) decides the change due.
  Future<PlacedWalkInSale> placeWalkInSale({
    required PosTicket ticket,
    required PaymentMethod paymentMethod,
    Money? amountTendered,
    String? customerName,
    Money? expectedTotal,
  }) {
    return ErrorMapper.guard(() async {
      final response = await _callable('placeWalkInSale').call<Object?>({
        'items': [
          for (final line in ticket.lines)
            {'productId': line.productId, 'quantity': line.quantity},
        ],
        'paymentMethod': paymentMethod.id,
        if (amountTendered != null)
          'amountTenderedCentavos': amountTendered.centavos,
        if (customerName != null && customerName.trim().isNotEmpty)
          'customerName': customerName.trim(),
        if (expectedTotal != null)
          'expectedTotalCentavos': expectedTotal.centavos,
      });
      return PlacedWalkInSale.fromJson(_asMap(response.data), paymentMethod);
    }, operation: 'complete the sale');
  }

  /// Moves an order to its next status. Owner only.
  Future<void> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
    String? note,
  }) {
    return ErrorMapper.guard(() async {
      await _callable('updateOrderStatus').call<Object?>({
        'orderId': orderId,
        'status': status.name,
        'note': note,
      });
    }, operation: 'update the order');
  }

  /// Creates or updates a product. Owner only.
  ///
  /// Selling prices are deliberately absent from the payload: the server derives them from
  /// the cost and the profit percentage so that the catalog can never disagree with the
  /// store's pricing policy.
  Future<SavedProduct> saveProduct({
    String? productId,
    required String name,
    required Money costPrice,
    required PricingMode pricingMode,
    Percentage? profitPercentage,
    String? barcode,
    String? brand,
    String? categoryId,
    String? description,
    String? imageUrl,
    String unit = 'pc',
    String source = 'manual',
    int lowStockThreshold = 0,
    int? initialStock,
    DateTime? expiryDate,
    bool isActive = true,
  }) {
    return ErrorMapper.guard(() async {
      final response = await _callable('saveProduct').call<Object?>({
        // Omitted rather than sent as null: absence is what tells the server this is a
        // new product rather than an edit.
        'productId': ?productId,
        'name': name,
        'barcode': barcode,
        'brand': brand,
        'categoryId': categoryId,
        'description': description,
        'imageUrl': imageUrl,
        'unit': unit,
        'source': source,
        'costPriceCentavos': costPrice.centavos,
        'pricingMode': pricingMode.toJson(),
        'profitBasisPoints': profitPercentage?.basisPoints,
        'lowStockThreshold': lowStockThreshold,
        'initialStock': ?initialStock,
        if (expiryDate != null)
          'expiryDateMillis': expiryDate.toUtc().millisecondsSinceEpoch,
        'isActive': isActive,
      });
      return SavedProduct.fromJson(_asMap(response.data));
    }, operation: 'save the product');
  }

  /// Hides a product from the catalog, or brings it back. Owner only.
  Future<void> setProductActive({
    required String productId,
    required bool isActive,
  }) {
    return ErrorMapper.guard(() async {
      await _callable(
        'setProductActive',
      ).call<Object?>({'productId': productId, 'isActive': isActive});
    }, operation: 'update the product');
  }

  /// Records a stock movement. A cashier may record everything except a restock or a cost
  /// change — the server enforces that, this just doesn't offer it in the UI.
  ///
  /// [quantity] is always a positive count; the [type] decides the direction, except for
  /// an adjustment, where [isDecrease] says which way the physical recount went.
  ///
  /// [expiryDate] only means anything with a restock, where it opens a new batch. [batchId]
  /// only means anything for a movement that removes stock (damage, expired, a decreasing
  /// adjustment) or a manual return: naming a batch targets it directly; leaving it out lets
  /// the server auto-select the oldest-expiring batch instead.
  Future<InventoryChange> adjustInventory({
    required String productId,
    required InventoryTransactionType type,
    required int quantity,
    String? reason,
    Money? unitCost,
    bool isDecrease = false,
    DateTime? expiryDate,
    String? batchId,
  }) {
    return ErrorMapper.guard(() async {
      final response = await _callable('adjustInventory').call<Object?>({
        'productId': productId,
        'type': type.name,
        'quantity': quantity,
        'reason': reason,
        if (unitCost != null) 'unitCostCentavos': unitCost.centavos,
        'direction': isDecrease ? 'decrease' : 'increase',
        if (expiryDate != null)
          'expiryDateMillis': expiryDate.toUtc().millisecondsSinceEpoch,
        'batchId': ?batchId,
      });
      return InventoryChange.fromJson(_asMap(response.data));
    }, operation: 'update the stock');
  }

  /// Logs an end-of-shift cash-drawer count against what was expected. Owner or cashier.
  ///
  /// A snapshot for the owner to review later, not a live balance — [expected] and
  /// [counted] are both amounts the caller worked out beforehand.
  Future<RecordedCashCount> recordCashCount({
    required Money expected,
    required Money counted,
    String? note,
  }) {
    return ErrorMapper.guard(() async {
      final response = await _callable('recordCashCount').call<Object?>({
        'expectedCentavos': expected.centavos,
        'countedCentavos': counted.centavos,
        'note': note,
      });
      return RecordedCashCount.fromJson(_asMap(response.data));
    }, operation: 'record the cash count');
  }

  /// Sets the store-wide default profit percentage. Owner only.
  ///
  /// Returns how many products were re-priced as a result, so the owner sees the size of
  /// what they just did rather than having to guess.
  Future<int> savePricingSettings(Percentage defaultProfit) {
    return ErrorMapper.guard(() async {
      final response = await _callable(
        'savePricingSettings',
        // Re-pricing the whole catalog takes longer than a normal call.
        timeout: const Duration(seconds: 60),
      ).call<Object?>({'defaultProfitBasisPoints': defaultProfit.basisPoints});
      final data = _asMap(response.data);
      return (data['repricedCount'] as num?)?.toInt() ?? 0;
    }, operation: 'save the pricing settings');
  }

  /// Replaces the GCash convenience fee table. Owner only.
  ///
  /// The server revalidates the tiers. The client checks them first so the owner gets
  /// inline feedback while editing, but the server's check is the one that counts.
  Future<void> saveGcashFeeTiers(GcashFeeSchedule schedule) {
    return ErrorMapper.guard(() async {
      await _callable(
        'saveGcashFeeTiers',
      ).call<Object?>({'tiers': schedule.toJson()});
    }, operation: 'save the GCash fees');
  }

  /// Sets or clears the store's GCash "Scan to Pay" QR code. Owner only.
  ///
  /// [imageUrl] is a Storage download URL already uploaded by the client — this call just
  /// records it. Pass `null` to remove the QR code and stop showing it at checkout.
  Future<void> saveGcashQr(String? imageUrl) {
    return ErrorMapper.guard(() async {
      await _callable('saveGcashQr').call<Object?>({'imageUrl': imageUrl});
    }, operation: 'save the GCash QR code');
  }

  /// Writes the categories and settings a brand-new store needs. Owner only, idempotent.
  Future<void> seedStore() {
    return ErrorMapper.guard(
      () async => _callable('seedStore').call<Object?>(),
      operation: 'set up the store',
    );
  }

  /// Turns the signed-in account into the store owner, using the one-time setup code.
  Future<void> claimStoreOwnership(String setupCode) {
    return ErrorMapper.guard(() async {
      await _callable(
        'claimStoreOwnership',
      ).call<Object?>({'setupCode': setupCode});
    }, operation: 'claim the store');
  }

  /// Grants or revokes owner access for another account. Owner only.
  Future<void> setUserRole({required String email, required String role}) {
    return ErrorMapper.guard(() async {
      await _callable(
        'setUserRole',
      ).call<Object?>({'email': email, 'role': role});
    }, operation: 'update that account');
  }

  static Map<String, Object?> _asMap(Object? data) {
    if (data is Map) return data.cast<String, Object?>();
    return const {};
  }
}
