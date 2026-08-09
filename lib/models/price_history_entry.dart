import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../core/money/money.dart';
import '../core/money/percentage.dart';
import '../features/pricing/domain/pricing_engine.dart';

/// What prompted a price to change.
enum PriceChangeReason {
  /// The owner edited the product's cost or profit settings.
  productEdited(label: 'Product edited'),

  /// A delivery was received at a different cost.
  restock(label: 'Restocked at a new cost'),

  /// The store-wide default profit percentage changed, re-pricing this product.
  storeDefaultChanged(label: 'Store default profit changed'),

  /// The product was first created.
  created(label: 'Product created');

  const PriceChangeReason({required this.label});

  final String label;

  static PriceChangeReason fromJson(Object? value) =>
      PriceChangeReason.values.firstWhere(
        (reason) => reason.name == value,
        orElse: () => PriceChangeReason.productEdited,
      );

  String toJson() => name;
}

/// One row of a product's pricing audit trail, at `productPriceHistory/{id}`.
///
/// Owner-readable only — it contains cost prices.
///
/// A row is appended every time a cost or a selling price changes, in the same write as
/// the change itself. Nothing overwrites or deletes these: the point of the trail is that
/// the owner can answer "what were we paying for this in June, and what were we charging?"
/// months later.
@immutable
class PriceHistoryEntry {
  const PriceHistoryEntry({
    required this.id,
    required this.productId,
    required this.productName,
    required this.reason,
    required this.newCostPrice,
    required this.newCashPrice,
    required this.newGcashPrice,
    required this.newProfitPercentage,
    required this.newPricingMode,
    this.oldCostPrice,
    this.oldCashPrice,
    this.oldGcashPrice,
    this.oldProfitPercentage,
    this.oldPricingMode,
    this.changedBy,
    this.changedByName,
    this.changedAt,
  });

  final String id;
  final String productId;

  /// Snapshot of the name at the time, so history survives a rename.
  final String productName;

  final PriceChangeReason reason;

  /// `null` on the first entry, when the product was created.
  final Money? oldCostPrice;
  final Money? oldCashPrice;
  final Money? oldGcashPrice;
  final Percentage? oldProfitPercentage;
  final PricingMode? oldPricingMode;

  final Money newCostPrice;
  final Money newCashPrice;
  final Money newGcashPrice;

  /// The percentage actually in force after the change — the store default for a standard
  /// product, the product's own for a custom one. Stored resolved so reading history does
  /// not require knowing what the store default was that day.
  final Percentage newProfitPercentage;

  final PricingMode newPricingMode;

  final String? changedBy;
  final String? changedByName;
  final DateTime? changedAt;

  bool get isInitial => oldCostPrice == null;

  bool get costChanged => oldCostPrice != null && oldCostPrice != newCostPrice;
  bool get cashPriceChanged =>
      oldCashPrice != null && oldCashPrice != newCashPrice;
  bool get gcashPriceChanged =>
      oldGcashPrice != null && oldGcashPrice != newGcashPrice;

  /// How much the cost moved, or `null` for the first entry.
  Money? get costDelta =>
      oldCostPrice == null ? null : newCostPrice - oldCostPrice!;

  /// True when the goods got more expensive to buy.
  bool? get costRose {
    final delta = costDelta;
    if (delta == null || delta.isZero) return null;
    return delta.isPositive;
  }

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'reason': reason.toJson(),
    'oldCostPriceCentavos': oldCostPrice?.centavos,
    'oldCashPriceCentavos': oldCashPrice?.centavos,
    'oldGcashPriceCentavos': oldGcashPrice?.centavos,
    'oldProfitBasisPoints': oldProfitPercentage?.basisPoints,
    'oldPricingMode': oldPricingMode?.toJson(),
    'newCostPriceCentavos': newCostPrice.centavos,
    'newCashPriceCentavos': newCashPrice.centavos,
    'newGcashPriceCentavos': newGcashPrice.centavos,
    'newProfitBasisPoints': newProfitPercentage.basisPoints,
    'newPricingMode': newPricingMode.toJson(),
    'changedBy': changedBy,
    'changedByName': changedByName,
    'changedAt': changedAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(changedAt!),
  };

  static PriceHistoryEntry fromFirestore(
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) => PriceHistoryEntry.fromJson(snapshot.id, snapshot.data() ?? const {});

  static PriceHistoryEntry fromJson(String id, Map<String, Object?> json) {
    Money? money(Object? value) => value == null ? null : Money.fromJson(value);
    Percentage? percentage(Object? value) =>
        value == null ? null : Percentage.fromJson(value);

    return PriceHistoryEntry(
      id: id,
      productId: (json['productId'] as String?) ?? '',
      productName: (json['productName'] as String?) ?? 'Removed product',
      reason: PriceChangeReason.fromJson(json['reason']),
      oldCostPrice: money(json['oldCostPriceCentavos']),
      oldCashPrice: money(json['oldCashPriceCentavos']),
      oldGcashPrice: money(json['oldGcashPriceCentavos']),
      oldProfitPercentage: percentage(json['oldProfitBasisPoints']),
      oldPricingMode: json['oldPricingMode'] == null
          ? null
          : PricingMode.fromJson(json['oldPricingMode']),
      newCostPrice: Money.fromJson(json['newCostPriceCentavos']),
      newCashPrice: Money.fromJson(json['newCashPriceCentavos']),
      newGcashPrice: Money.fromJson(json['newGcashPriceCentavos']),
      newProfitPercentage: Percentage.fromJson(json['newProfitBasisPoints']),
      newPricingMode: PricingMode.fromJson(json['newPricingMode']),
      changedBy: json['changedBy'] as String?,
      changedByName: json['changedByName'] as String?,
      changedAt: switch (json['changedAt']) {
        Timestamp() => (json['changedAt']! as Timestamp).toDate(),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PriceHistoryEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'PriceHistoryEntry($productName, cost: $oldCostPrice → $newCostPrice)';
}
