import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../core/money/money.dart';
import 'payment_method.dart';

/// Where an order is in the store's workflow.
///
/// The happy path runs pending → confirmed → preparing → ready → completed. An order can
/// be cancelled from any state before it is completed; a completed order is final, because
/// completing it is what writes the sales record and consumes the stock for good.
enum OrderStatus {
  pending(label: 'Pending', description: 'Waiting for the store to confirm.'),
  confirmed(
    label: 'Confirmed',
    description: 'The store has accepted your order.',
  ),
  preparing(label: 'Preparing', description: 'Your order is being packed.'),
  ready(label: 'Ready', description: 'Ready for pickup or delivery.'),
  completed(label: 'Completed', description: 'Handed over and paid.'),
  cancelled(label: 'Cancelled', description: 'This order was cancelled.');

  const OrderStatus({required this.label, required this.description});

  final String label;
  final String description;

  static OrderStatus fromJson(Object? value) => OrderStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => OrderStatus.pending,
  );

  String toJson() => name;

  /// Statuses that still count as live work for the owner.
  bool get isOpen =>
      this != OrderStatus.completed && this != OrderStatus.cancelled;

  /// Once true, the order can no longer change.
  bool get isFinal => !isOpen;

  /// Whether reserved stock is still held by this order.
  ///
  /// Stock is taken when the order is placed so two customers cannot buy the same last
  /// pack. Cancelling gives it back; completing keeps it gone.
  bool get holdsStock => isOpen;

  /// The statuses this one may move to.
  ///
  /// Encoding the workflow here rather than in the owner's screen means the same rules
  /// apply to the callable function that performs the change.
  Set<OrderStatus> get allowedNext => switch (this) {
    OrderStatus.pending => {OrderStatus.confirmed, OrderStatus.cancelled},
    OrderStatus.confirmed => {OrderStatus.preparing, OrderStatus.cancelled},
    OrderStatus.preparing => {OrderStatus.ready, OrderStatus.cancelled},
    OrderStatus.ready => {OrderStatus.completed, OrderStatus.cancelled},
    OrderStatus.completed => const {},
    OrderStatus.cancelled => const {},
  };

  bool canMoveTo(OrderStatus next) => allowedNext.contains(next);

  /// Position in the progress indicator shown to the customer, or `null` for cancelled.
  int? get trackingStep => switch (this) {
    OrderStatus.pending => 0,
    OrderStatus.confirmed => 1,
    OrderStatus.preparing => 2,
    OrderStatus.ready => 3,
    OrderStatus.completed => 4,
    OrderStatus.cancelled => null,
  };

  /// Number of steps in the customer-facing tracker.
  static const int trackingStepCount = 5;
}

/// Whether the buyer had an account at the time of the order.
enum CustomerType {
  guest,
  registered;

  static CustomerType fromJson(Object? value) =>
      value == 'guest' ? CustomerType.guest : CustomerType.registered;

  String toJson() => name;

  String get label => this == CustomerType.guest ? 'Guest' : 'Registered';
}

/// One line of an order, frozen at the moment the order was placed.
///
/// The prices here are a **snapshot**, not a reference. If Piattos moves from ₱18 to ₱20
/// tomorrow, this line still says ₱18, because that is what the customer paid. Nothing in
/// the app recomputes a historical total from the current product document.
@immutable
class OrderItem {
  const OrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.cashPriceAtPurchase,
    required this.gcashPriceAtPurchase,
    required this.selectedUnitPrice,
    required this.lineTotal,
    this.brand,
    this.unit = 'pc',
    this.imageUrl,
  });

  final String productId;

  /// The product's name when the order was placed, kept so a later rename or a
  /// deactivated product does not blank out order history.
  final String productName;
  final String? brand;
  final String unit;
  final String? imageUrl;

  final int quantity;

  /// Both price lists are recorded, not just the one used, so the owner can see what the
  /// same basket would have cost under the other payment method.
  final Money cashPriceAtPurchase;
  final Money gcashPriceAtPurchase;

  /// The price actually charged per unit — one of the two above, chosen by the order's
  /// payment method.
  final Money selectedUnitPrice;

  /// `selectedUnitPrice × quantity`, stored rather than derived so a historical order can
  /// be displayed without re-running any arithmetic.
  final Money lineTotal;

  /// Recomputes the line total from its parts. Used by the server to verify a submitted
  /// order and by tests; it must always equal [lineTotal].
  Money get recomputedLineTotal => selectedUnitPrice * quantity;

  bool get isConsistent => recomputedLineTotal == lineTotal;

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'brand': brand,
    'unit': unit,
    'imageUrl': imageUrl,
    'quantity': quantity,
    'cashPriceCentavos': cashPriceAtPurchase.centavos,
    'gcashPriceCentavos': gcashPriceAtPurchase.centavos,
    'selectedUnitPriceCentavos': selectedUnitPrice.centavos,
    'lineTotalCentavos': lineTotal.centavos,
  };

  static OrderItem fromJson(Map<String, Object?> json) {
    return OrderItem(
      productId: (json['productId'] as String?) ?? '',
      productName: (json['productName'] as String?) ?? 'Removed product',
      brand: json['brand'] as String?,
      unit: (json['unit'] as String?) ?? 'pc',
      imageUrl: json['imageUrl'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      cashPriceAtPurchase: Money.fromJson(json['cashPriceCentavos']),
      gcashPriceAtPurchase: Money.fromJson(json['gcashPriceCentavos']),
      selectedUnitPrice: Money.fromJson(json['selectedUnitPriceCentavos']),
      lineTotal: Money.fromJson(json['lineTotalCentavos']),
    );
  }

  @override
  String toString() =>
      'OrderItem($productName ×$quantity @ $selectedUnitPrice = $lineTotal)';
}

/// Contact and fulfilment details captured at checkout.
///
/// A guest supplies these at checkout; a registered customer has them prefilled from their
/// profile and can still change them per order. They are copied onto the order rather than
/// referenced, so editing a profile never rewrites where a past order went.
@immutable
class OrderContact {
  const OrderContact({
    required this.name,
    required this.phoneNumber,
    this.address,
    this.notes,
  });

  final String name;
  final String phoneNumber;

  /// Absent for pickup orders.
  final String? address;

  /// Free-text instructions: "leave with the tindahan next door".
  final String? notes;

  bool get isDelivery => address?.trim().isNotEmpty ?? false;

  Map<String, Object?> toJson() => {
    'name': name,
    'phoneNumber': phoneNumber,
    'address': address,
    'notes': notes,
  };

  static OrderContact fromJson(Map<String, Object?> json) => OrderContact(
    name: (json['name'] as String?) ?? '',
    phoneNumber: (json['phoneNumber'] as String?) ?? '',
    address: json['address'] as String?,
    notes: json['notes'] as String?,
  );
}

/// A customer order.
///
/// Maps to `orders/{id}`, readable by the customer who placed it and by the owner. The
/// per-line cost snapshot needed for profit reporting is **not** here — it lives in
/// `orders/{id}/private/costs` as an [OrderCostSnapshot] so the customer cannot read what
/// the store paid.
///
/// Orders are only ever written by the server. The client assembles a cart, previews a
/// total, and calls `placeOrder`; the function re-derives every price from Firestore and
/// writes the document. The totals below are therefore the server's figures, which is what
/// makes them safe to display as "what you paid".
@immutable
class StoreOrder {
  const StoreOrder({
    required this.id,
    required this.customerId,
    required this.customerType,
    required this.paymentMethod,
    required this.status,
    required this.items,
    required this.subtotal,
    required this.convenienceFee,
    required this.total,
    required this.contact,
    this.orderNumber,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.statusHistory = const [],
  });

  final String id;

  /// A short human-readable reference the customer can quote at the counter.
  final String? orderNumber;

  final String customerId;
  final CustomerType customerType;
  final PaymentMethod paymentMethod;
  final OrderStatus status;

  final List<OrderItem> items;

  /// Sum of the line totals, before any convenience fee.
  final Money subtotal;

  /// The GCash convenience fee — charged **once for the whole order**, ₱0 for cash.
  final Money convenienceFee;

  /// `subtotal + convenienceFee`. What the customer actually pays.
  final Money total;

  final OrderContact contact;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  /// Every status the order has passed through, for the customer's tracking screen.
  final List<OrderStatusChange> statusHistory;

  int get itemCount =>
      items.fold(0, (running, item) => running + item.quantity);

  int get lineCount => items.length;

  bool get isGcash => paymentMethod == PaymentMethod.gcash;

  bool get wasPlacedByGuest => customerType == CustomerType.guest;

  /// Recomputes the subtotal from the lines. Used to verify a document, never to display:
  /// [subtotal] as written by the server is the authority.
  Money get recomputedSubtotal =>
      Money.sum(items.map((item) => item.lineTotal));

  /// Whether the stored totals agree with the stored lines. A `false` here means the
  /// document was tampered with or written by a buggy build, and the UI shows the stored
  /// values with a warning rather than silently "fixing" them.
  bool get isConsistent =>
      items.every((item) => item.isConsistent) &&
      recomputedSubtotal == subtotal &&
      subtotal + convenienceFee == total;

  StoreOrder copyWith({
    OrderStatus? status,
    DateTime? updatedAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancellationReason,
    List<OrderStatusChange>? statusHistory,
  }) {
    return StoreOrder(
      id: id,
      orderNumber: orderNumber,
      customerId: customerId,
      customerType: customerType,
      paymentMethod: paymentMethod,
      status: status ?? this.status,
      items: items,
      subtotal: subtotal,
      convenienceFee: convenienceFee,
      total: total,
      contact: contact,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      statusHistory: statusHistory ?? this.statusHistory,
    );
  }

  Map<String, Object?> toJson() => {
    'orderNumber': orderNumber,
    'customerId': customerId,
    'customerType': customerType.toJson(),
    'paymentMethod': paymentMethod.toJson(),
    'status': status.toJson(),
    'items': items.map((item) => item.toJson()).toList(),
    'subtotalCentavos': subtotal.centavos,
    'convenienceFeeCentavos': convenienceFee.centavos,
    'totalCentavos': total.centavos,
    'contact': contact.toJson(),
    'createdAt': createdAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(createdAt!),
    'updatedAt': FieldValue.serverTimestamp(),
    'completedAt': completedAt == null
        ? null
        : Timestamp.fromDate(completedAt!),
    'cancelledAt': cancelledAt == null
        ? null
        : Timestamp.fromDate(cancelledAt!),
    'cancellationReason': cancellationReason,
    'statusHistory': statusHistory.map((change) => change.toJson()).toList(),
  };

  static StoreOrder fromFirestore(
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) => StoreOrder.fromJson(snapshot.id, snapshot.data() ?? const {});

  static StoreOrder fromJson(String id, Map<String, Object?> json) {
    return StoreOrder(
      id: id,
      orderNumber: json['orderNumber'] as String?,
      customerId: (json['customerId'] as String?) ?? '',
      customerType: CustomerType.fromJson(json['customerType']),
      paymentMethod: PaymentMethod.fromJson(json['paymentMethod']),
      status: OrderStatus.fromJson(json['status']),
      items: (json['items'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((raw) => OrderItem.fromJson(raw.cast<String, Object?>()))
          .toList(),
      subtotal: Money.fromJson(json['subtotalCentavos']),
      convenienceFee: Money.fromJson(json['convenienceFeeCentavos']),
      total: Money.fromJson(json['totalCentavos']),
      contact: OrderContact.fromJson(
        (json['contact'] as Map<Object?, Object?>? ?? const {})
            .cast<String, Object?>(),
      ),
      createdAt: readTimestamp(json['createdAt']),
      updatedAt: readTimestamp(json['updatedAt']),
      completedAt: readTimestamp(json['completedAt']),
      cancelledAt: readTimestamp(json['cancelledAt']),
      cancellationReason: json['cancellationReason'] as String?,
      statusHistory: (json['statusHistory'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((raw) => OrderStatusChange.fromJson(raw.cast<String, Object?>()))
          .toList(),
    );
  }

  static DateTime? readTimestamp(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    DateTime() => value,
    int() => DateTime.fromMillisecondsSinceEpoch(value),
    _ => null,
  };

  @override
  bool operator ==(Object other) => other is StoreOrder && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'StoreOrder($id, ${status.name}, $total)';
}

/// One entry in an order's status trail.
@immutable
class OrderStatusChange {
  const OrderStatusChange({
    required this.status,
    required this.changedAt,
    this.changedBy,
    this.note,
  });

  final OrderStatus status;
  final DateTime changedAt;

  /// The uid that made the change — the owner for operational moves, the customer for a
  /// self-service cancellation.
  final String? changedBy;
  final String? note;

  Map<String, Object?> toJson() => {
    'status': status.toJson(),
    'changedAt': Timestamp.fromDate(changedAt),
    'changedBy': changedBy,
    'note': note,
  };

  static OrderStatusChange fromJson(Map<String, Object?> json) =>
      OrderStatusChange(
        status: OrderStatus.fromJson(json['status']),
        changedAt:
            StoreOrder.readTimestamp(json['changedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        changedBy: json['changedBy'] as String?,
        note: json['note'] as String?,
      );
}

/// The owner-only cost side of an order, stored at `orders/{id}/private/costs`.
///
/// Profit reporting needs to know what each line cost the store, but a customer reading
/// their own order must not see it. Splitting it into a subdocument is what lets the
/// security rules say yes to one and no to the other.
@immutable
class OrderCostSnapshot {
  const OrderCostSnapshot({
    required this.orderId,
    required this.lines,
    required this.totalProductCost,
  });

  final String orderId;
  final List<OrderCostLine> lines;

  /// What the goods in this order cost the store to acquire.
  final Money totalProductCost;

  Map<String, Object?> toJson() => {
    'lines': lines.map((line) => line.toJson()).toList(),
    'totalProductCostCentavos': totalProductCost.centavos,
  };

  static OrderCostSnapshot fromJson(String orderId, Map<String, Object?> json) {
    return OrderCostSnapshot(
      orderId: orderId,
      lines: (json['lines'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((raw) => OrderCostLine.fromJson(raw.cast<String, Object?>()))
          .toList(),
      totalProductCost: Money.fromJson(json['totalProductCostCentavos']),
    );
  }
}

/// What one order line cost the store.
@immutable
class OrderCostLine {
  const OrderCostLine({
    required this.productId,
    required this.quantity,
    required this.costPriceAtPurchase,
  });

  final String productId;
  final int quantity;

  /// The cost price recorded against the product when the order was placed. Frozen, so a
  /// later restock at a different cost does not rewrite this order's profit.
  final Money costPriceAtPurchase;

  Money get lineCost => costPriceAtPurchase * quantity;

  Map<String, Object?> toJson() => {
    'productId': productId,
    'quantity': quantity,
    'costPriceCentavos': costPriceAtPurchase.centavos,
  };

  static OrderCostLine fromJson(Map<String, Object?> json) => OrderCostLine(
    productId: (json['productId'] as String?) ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    costPriceAtPurchase: Money.fromJson(json['costPriceCentavos']),
  );
}
