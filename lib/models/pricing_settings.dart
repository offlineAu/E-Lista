import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../core/money/percentage.dart';

/// Store-wide pricing configuration, at `settings/pricing`.
///
/// Owner-readable and owner-writable only — the default profit percentage is business
/// information a customer has no reason to see, and it is not needed to display a price.
///
/// The GCash convenience fee tiers live in a *separate* document, `settings/gcash_fees`,
/// which is world-readable, because a customer must be able to see the fee that will be
/// added to their order before they confirm it.
@immutable
class PricingSettings {
  const PricingSettings({
    required this.defaultProfitPercentage,
    this.updatedAt,
    this.updatedBy,
  });

  /// What a brand-new store starts with: 20% on everything.
  static const PricingSettings defaults = PricingSettings(
    defaultProfitPercentage: Percentage.fromPercent(20),
  );

  /// Applied to every product whose pricing mode is `standard`.
  ///
  /// Changing this re-prices all of them, and none of the products with a custom
  /// percentage. That recalculation happens server-side so the two price lists and the
  /// price history stay in step.
  final Percentage defaultProfitPercentage;

  final DateTime? updatedAt;
  final String? updatedBy;

  /// Whether a percentage is usable as a profit figure.
  ///
  /// The upper bound exists because the GCash formula divides by `1 - margin`: at 100% the
  /// price is infinite, and anything near it produces prices no one would type on purpose.
  static String? describeProblem(Percentage percentage) {
    if (percentage.isNegative) {
      return 'Profit cannot be negative.';
    }
    if (percentage.basisPoints >= maximumProfitBasisPoints) {
      return 'Profit must be below ${maximumProfit.format()}. '
          'GCash pricing divides by the remaining margin, so 100% has no price.';
    }
    return null;
  }

  /// Highest profit percentage the settings accept, exclusive.
  static const int maximumProfitBasisPoints = 9000;
  static const Percentage maximumProfit = Percentage.fromBasisPoints(
    maximumProfitBasisPoints,
  );

  PricingSettings copyWith({
    Percentage? defaultProfitPercentage,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return PricingSettings(
      defaultProfitPercentage:
          defaultProfitPercentage ?? this.defaultProfitPercentage,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  Map<String, Object?> toJson() => {
    'defaultProfitBasisPoints': defaultProfitPercentage.basisPoints,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': updatedBy,
  };

  /// Reads the document, falling back to [defaults] when it does not exist yet so a store
  /// that has never opened Pricing Settings still prices correctly.
  static PricingSettings fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) return defaults;
    final raw = json['defaultProfitBasisPoints'];
    return PricingSettings(
      defaultProfitPercentage: raw == null
          ? defaults.defaultProfitPercentage
          : Percentage.fromJson(raw),
      updatedAt: switch (json['updatedAt']) {
        Timestamp() => (json['updatedAt']! as Timestamp).toDate(),
        _ => null,
      },
      updatedBy: json['updatedBy'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PricingSettings &&
      other.defaultProfitPercentage == defaultProfitPercentage;

  @override
  int get hashCode => defaultProfitPercentage.hashCode;

  @override
  String toString() => 'PricingSettings(default: $defaultProfitPercentage)';
}
