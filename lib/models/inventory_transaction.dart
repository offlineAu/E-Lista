import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../core/money/money.dart';

/// Why stock moved.
///
/// Stock quantity alone is a number with no explanation; these types are what make the
/// inventory auditable. Every change to `products/{id}.stockQuantity` writes one of these
/// in the same Firestore transaction, so the ledger and the balance can never disagree.
enum InventoryTransactionType {
  /// Goods arriving from the supplier. Increases stock.
  restock(label: 'Restock', increasesStock: true),

  /// Sold to a customer. Decreases stock; written when the order is placed, so two
  /// customers cannot both buy the last pack.
  sale(label: 'Sale', increasesStock: false),

  /// A manual correction after a physical count. May go either way.
  adjustment(label: 'Adjustment', increasesStock: null),

  /// Broken, crushed or spoiled goods. Decreases stock.
  damage(label: 'Damaged', increasesStock: false),

  /// Past its date. Decreases stock.
  expired(label: 'Expired', increasesStock: false),

  /// Came back from the customer, or an order was cancelled and its hold released.
  /// Increases stock.
  returned(label: 'Returned', increasesStock: true);

  const InventoryTransactionType({
    required this.label,
    required this.increasesStock,
  });

  final String label;

  /// `true` always adds, `false` always removes, `null` may do either (adjustments).
  final bool? increasesStock;

  static InventoryTransactionType fromJson(Object? value) =>
      InventoryTransactionType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => InventoryTransactionType.adjustment,
      );

  String toJson() => name;

  /// Types the owner may record by hand. Sales are written by the order flow only.
  static const List<InventoryTransactionType> manuallyRecordable = [
    restock,
    adjustment,
    damage,
    expired,
    returned,
  ];

  /// Whether recording this type should ask the owner for a reason.
  bool get requiresReason => switch (this) {
    InventoryTransactionType.adjustment ||
    InventoryTransactionType.damage ||
    InventoryTransactionType.expired => true,
    InventoryTransactionType.restock ||
    InventoryTransactionType.sale ||
    InventoryTransactionType.returned => false,
  };

  /// Whether the owner may enter a new receipt cost alongside this movement. A delivery
  /// at a new price is the normal way a product's cost changes.
  bool get acceptsCostUpdate => this == InventoryTransactionType.restock;
}

/// What caused a stock movement, for tracing it back.
enum InventoryReferenceType {
  order,
  manual,
  import;

  static InventoryReferenceType fromJson(Object? value) =>
      InventoryReferenceType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => InventoryReferenceType.manual,
      );

  String toJson() => name;
}

/// One line of the inventory ledger, at `inventoryTransactions/{id}`.
///
/// Owner-readable only: it carries stock levels and, for restocks, the receipt cost.
///
/// Both the before and after balances are stored, not just the delta. That redundancy is
/// deliberate — it is what lets the owner see that the ledger is internally consistent
/// without replaying every row from the beginning.
@immutable
class InventoryTransaction {
  const InventoryTransaction({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.previousStock,
    required this.newStock,
    required this.referenceType,
    this.referenceId,
    this.unitCost,
    this.reason,
    this.performedBy,
    this.performedByName,
    this.createdAt,
  });

  final String id;
  final String productId;

  /// Snapshot of the name, so history stays readable after a rename or a deletion.
  final String productName;

  final InventoryTransactionType type;

  /// Signed change: `+24` for a delivery, `-3` for a sale. Always equals
  /// `newStock - previousStock`.
  final int quantity;

  final int previousStock;
  final int newStock;

  final InventoryReferenceType referenceType;

  /// The order id for a sale or a cancellation-return; `null` for a manual movement.
  final String? referenceId;

  /// Receipt cost per unit for a restock, when the owner entered one.
  final Money? unitCost;

  /// Why, for adjustments, damage and expiry.
  final String? reason;

  final String? performedBy;
  final String? performedByName;
  final DateTime? createdAt;

  bool get isIncrease => quantity > 0;

  /// What the goods in this movement were worth at the recorded cost, when known.
  Money? get totalCost => unitCost == null ? null : unitCost! * quantity.abs();

  /// Whether the stored balances agree with the stored change.
  bool get isConsistent => previousStock + quantity == newStock;

  /// `+24` / `-3`, for the history list.
  String get signedQuantityLabel => quantity > 0 ? '+$quantity' : '$quantity';

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'type': type.toJson(),
    'quantity': quantity,
    'previousStock': previousStock,
    'newStock': newStock,
    'referenceType': referenceType.toJson(),
    'referenceId': referenceId,
    'unitCostCentavos': unitCost?.centavos,
    'reason': reason,
    'performedBy': performedBy,
    'performedByName': performedByName,
    'createdAt': createdAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(createdAt!),
  };

  static InventoryTransaction fromFirestore(
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) => InventoryTransaction.fromJson(snapshot.id, snapshot.data() ?? const {});

  static InventoryTransaction fromJson(String id, Map<String, Object?> json) {
    final rawCost = json['unitCostCentavos'];
    return InventoryTransaction(
      id: id,
      productId: (json['productId'] as String?) ?? '',
      productName: (json['productName'] as String?) ?? 'Removed product',
      type: InventoryTransactionType.fromJson(json['type']),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      previousStock: (json['previousStock'] as num?)?.toInt() ?? 0,
      newStock: (json['newStock'] as num?)?.toInt() ?? 0,
      referenceType: InventoryReferenceType.fromJson(json['referenceType']),
      referenceId: json['referenceId'] as String?,
      unitCost: rawCost == null ? null : Money.fromJson(rawCost),
      reason: json['reason'] as String?,
      performedBy: json['performedBy'] as String?,
      performedByName: json['performedByName'] as String?,
      createdAt: switch (json['createdAt']) {
        Timestamp() => (json['createdAt']! as Timestamp).toDate(),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InventoryTransaction && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'InventoryTransaction($productName ${type.name} $signedQuantityLabel '
      '→ $newStock)';
}
