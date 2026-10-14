import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../core/money/money.dart';

/// A far-future date stored for a batch that never expires.
///
/// FEFO orders batches by `expiryDate` ascending, and Firestore sorts `null` *before* every
/// other value in ascending order — exactly backwards for "sell this last." Storing a fixed
/// sentinel instead keeps `expiryDate` always populated and always orderable, with
/// [ProductBatch.hasExpiry] carrying the real meaning for display.
final DateTime noExpirySentinel = DateTime.utc(9999, 12, 31);

/// One delivery's worth of stock, at `productBatches/{id}`.
///
/// Owner- and cashier-readable, Cloud-Function-written only. Unlike the product's price
/// history, this is not append-only: [remainingQuantity] decrements in place as FEFO
/// consumes the batch, and a write-off (damage, expiry, a cancelled sale's restore) can
/// increment it back. The document itself is never deleted, so a sale or a ledger row from
/// months ago can still resolve the batch it drew from.
@immutable
class ProductBatch {
  const ProductBatch({
    required this.id,
    required this.productId,
    required this.productName,
    required this.initialQuantity,
    required this.remainingQuantity,
    required this.unitCost,
    required this.expiryDate,
    required this.hasExpiry,
    this.sourceReferenceType,
    this.sourceTransactionId,
    this.receivedAt,
    this.createdBy,
    this.createdByName,
  });

  final String id;
  final String productId;

  /// Snapshot of the name at the time, so history survives a rename.
  final String productName;

  /// What this batch started with. Never changes after creation.
  final int initialQuantity;

  /// What is left to sell or write off. Decremented by sales and by damage/expired/
  /// adjustment write-offs; incremented back when a sale drawing from it is cancelled.
  final int remainingQuantity;

  /// The receipt cost for this specific delivery, kept even if a later restock changes it.
  final Money unitCost;

  /// The date this batch should be sold by. A batch with no known expiry carries
  /// [noExpirySentinel] here — check [hasExpiry] for what to actually show.
  final DateTime expiryDate;

  /// False when the owner did not record an expiry for this batch.
  final bool hasExpiry;

  /// How this batch entered stock: `'manual'` (a restock or opening stock the owner typed
  /// in), `'import'` (a catalog import's opening stock), or `null` for a batch predating
  /// this field.
  final String? sourceReferenceType;

  /// The `inventoryTransactions` row that created this batch, for cross-reference.
  final String? sourceTransactionId;

  final DateTime? receivedAt;
  final String? createdBy;
  final String? createdByName;

  bool get isDepleted => remainingQuantity <= 0;

  /// How many units of this batch have been sold or written off so far.
  int get consumedQuantity => initialQuantity - remainingQuantity;

  /// What is left of this batch is worth, at cost — the write-off the owner is exposed to
  /// if none of it sells before [expiryDate].
  Money get remainingValue => unitCost * remainingQuantity;

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'initialQuantity': initialQuantity,
    'remainingQuantity': remainingQuantity,
    'unitCostCentavos': unitCost.centavos,
    'expiryDate': Timestamp.fromDate(expiryDate),
    'hasExpiry': hasExpiry,
    'sourceReferenceType': sourceReferenceType,
    'sourceTransactionId': sourceTransactionId,
    'receivedAt': receivedAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(receivedAt!),
    'createdBy': createdBy,
    'createdByName': createdByName,
  };

  static ProductBatch fromFirestore(
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) => ProductBatch.fromJson(snapshot.id, snapshot.data() ?? const {});

  static ProductBatch fromJson(String id, Map<String, Object?> json) {
    return ProductBatch(
      id: id,
      productId: (json['productId'] as String?) ?? '',
      productName: (json['productName'] as String?) ?? 'Removed product',
      initialQuantity: (json['initialQuantity'] as num?)?.toInt() ?? 0,
      remainingQuantity: (json['remainingQuantity'] as num?)?.toInt() ?? 0,
      unitCost: Money.fromJson(json['unitCostCentavos']),
      expiryDate: _readTimestamp(json['expiryDate']) ?? noExpirySentinel,
      hasExpiry: (json['hasExpiry'] as bool?) ?? false,
      sourceReferenceType: json['sourceReferenceType'] as String?,
      sourceTransactionId: json['sourceTransactionId'] as String?,
      receivedAt: _readTimestamp(json['receivedAt']),
      createdBy: json['createdBy'] as String?,
      createdByName: json['createdByName'] as String?,
    );
  }

  static DateTime? _readTimestamp(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    DateTime() => value,
    _ => null,
  };

  @override
  bool operator ==(Object other) => other is ProductBatch && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ProductBatch($productName, $remainingQuantity/$initialQuantity left, '
      'expires ${hasExpiry ? expiryDate : 'never'})';
}

/// The total write-off exposure across a set of batches — what is left of each, at cost.
///
/// Shared by the inventory screen's banner, the dashboard's alert, and the expiring-batches
/// list, so the figure is computed the same way everywhere it appears.
Money expiringSoonValue(Iterable<ProductBatch> batches) => batches.fold(
  Money.zero,
  (total, batch) => total + batch.remainingValue,
);
