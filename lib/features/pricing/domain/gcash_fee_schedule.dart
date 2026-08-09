import 'package:meta/meta.dart';

import '../../../core/money/money.dart';

/// One configurable band of the GCash convenience fee table.
///
/// A tier covers an inclusive range of GCash subtotals and charges a single flat fee for
/// the whole transaction. `₱0 – ₱99.99 → ₱0.50` is
/// `GcashFeeTier(min: ₱0, max: ₱99.99, fee: ₱0.50)`.
@immutable
class GcashFeeTier {
  const GcashFeeTier({required this.min, required this.max, required this.fee});

  /// Inclusive lower bound of the subtotal range.
  final Money min;

  /// Inclusive upper bound, or `null` for the open-ended top tier.
  final Money? max;

  /// The flat fee charged once for the whole transaction.
  final Money fee;

  bool get isOpenEnded => max == null;

  bool contains(Money subtotal) =>
      subtotal >= min && (max == null || subtotal <= max!);

  /// How the range reads to the owner, e.g. `₱100 – ₱299.99` or `₱1,000 and above`.
  String get rangeLabel => max == null
      ? '${min.format()} and above'
      : '${min.format()} – ${max!.format()}';

  GcashFeeTier copyWith({Money? min, Object? max = _unset, Money? fee}) {
    return GcashFeeTier(
      min: min ?? this.min,
      max: identical(max, _unset) ? this.max : max as Money?,
      fee: fee ?? this.fee,
    );
  }

  Map<String, Object?> toJson() => {
    'minCentavos': min.centavos,
    'maxCentavos': max?.centavos,
    'feeCentavos': fee.centavos,
  };

  static GcashFeeTier fromJson(Map<String, Object?> json) {
    final rawMax = json['maxCentavos'];
    return GcashFeeTier(
      min: Money.fromJson(json['minCentavos']),
      max: rawMax == null ? null : Money.fromJson(rawMax),
      fee: Money.fromJson(json['feeCentavos']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GcashFeeTier &&
      other.min == min &&
      other.max == max &&
      other.fee == fee;

  @override
  int get hashCode => Object.hash(min, max, fee);

  @override
  String toString() => 'GcashFeeTier($rangeLabel → ${fee.format()})';

  static const Object _unset = Object();
}

/// Raised when a tier table could not produce one unambiguous fee for every subtotal.
class GcashFeeConfigException implements Exception {
  const GcashFeeConfigException(this.message);

  /// Phrased for the owner editing the tiers, not for a log file.
  final String message;

  @override
  String toString() => message;
}

/// The store's GCash convenience fee table.
///
/// The fee is charged **once per transaction**, never per product: an order of two items
/// at ₱18.75 and one at ₱25.00 has a subtotal of ₱62.50, falls in the ₱0–₱99.99 tier, and
/// pays ₱0.50 once, for ₱63.00.
///
/// The table lives in Firestore at `settings/gcash_fees` and is edited by the owner. It is
/// never hard-coded into a screen; [defaultSchedule] is only the table a brand-new store
/// starts with.
@immutable
class GcashFeeSchedule {
  const GcashFeeSchedule._(this.tiers);

  /// The tiers, sorted by lower bound, validated to be gapless and non-overlapping.
  final List<GcashFeeTier> tiers;

  /// The table a new store starts with. Editable from Pricing Settings afterwards.
  static final GcashFeeSchedule defaultSchedule = GcashFeeSchedule.validated([
    GcashFeeTier(
      min: Money.zero,
      max: const Money.fromCentavos(9999),
      fee: const Money.fromCentavos(50),
    ),
    const GcashFeeTier(
      min: Money.fromCentavos(10000),
      max: Money.fromCentavos(29999),
      fee: Money.fromCentavos(100),
    ),
    const GcashFeeTier(
      min: Money.fromCentavos(30000),
      max: Money.fromCentavos(49999),
      fee: Money.fromCentavos(200),
    ),
    const GcashFeeTier(
      min: Money.fromCentavos(50000),
      max: Money.fromCentavos(99999),
      fee: Money.fromCentavos(300),
    ),
    const GcashFeeTier(
      min: Money.fromCentavos(100000),
      max: null,
      fee: Money.fromCentavos(500),
    ),
  ]);

  /// Validates [tiers] and returns a usable schedule, or throws
  /// [GcashFeeConfigException] with a message the owner can act on.
  ///
  /// Every possible subtotal must resolve to exactly one fee, so the table must start at
  /// ₱0, end open-ended, and neither overlap nor leave gaps.
  factory GcashFeeSchedule.validated(List<GcashFeeTier> tiers) {
    final problem = describeProblem(tiers);
    if (problem != null) throw GcashFeeConfigException(problem);

    final sorted = [...tiers]..sort((a, b) => a.min.compareTo(b.min));
    return GcashFeeSchedule._(List.unmodifiable(sorted));
  }

  /// The first validation problem in [tiers], or `null` when the table is usable.
  ///
  /// Returning the message instead of throwing lets the tier editor show inline feedback
  /// while the owner is still typing.
  static String? describeProblem(List<GcashFeeTier> tiers) {
    if (tiers.isEmpty) {
      return 'Add at least one fee tier so every GCash order has a fee.';
    }

    final sorted = [...tiers]..sort((a, b) => a.min.compareTo(b.min));

    for (var i = 0; i < sorted.length; i++) {
      final tier = sorted[i];
      final label = 'Tier ${i + 1}';

      if (tier.min.isNegative) {
        return '$label starts below ₱0.';
      }
      if (tier.fee.isNegative) {
        return "$label's fee cannot be negative.";
      }
      if (tier.max != null && tier.max! < tier.min) {
        return '$label ends at ${tier.max!.format()}, which is before it starts at '
            '${tier.min.format()}.';
      }
      if (tier.isOpenEnded && i != sorted.length - 1) {
        return '$label has no upper limit, so it must be the last tier.';
      }
    }

    if (!sorted.first.min.isZero) {
      return 'The first tier must start at ₱0 so small orders are covered.';
    }
    if (!sorted.last.isOpenEnded) {
      return 'The last tier must have no upper limit so large orders are covered.';
    }

    for (var i = 1; i < sorted.length; i++) {
      final previous = sorted[i - 1];
      final current = sorted[i];
      // Only the last tier may be open-ended, so `previous.max` is non-null here.
      final expected = previous.max! + const Money.fromCentavos(1);

      if (current.min < expected) {
        return 'Tier $i and tier ${i + 1} overlap at ${current.min.format()}. '
            'Ranges must not cover the same amount twice.';
      }
      if (current.min > expected) {
        return 'Nothing covers ${expected.format()}. Tier $i should end just before '
            'tier ${i + 1} starts.';
      }
    }

    return null;
  }

  /// The single fee for a GCash [subtotal] — the sum of the GCash line totals, before the
  /// fee itself is added.
  Money feeFor(Money subtotal) {
    if (subtotal.isNegative) {
      throw const GcashFeeConfigException(
        'A GCash subtotal cannot be negative.',
      );
    }
    for (final tier in tiers) {
      if (tier.contains(subtotal)) return tier.fee;
    }
    // Unreachable for a validated schedule, which is gapless from ₱0 upwards.
    throw GcashFeeConfigException(
      'No GCash fee tier covers ${subtotal.format()}.',
    );
  }

  /// The tier a [subtotal] falls into, for showing the owner which band applied.
  GcashFeeTier tierFor(Money subtotal) {
    for (final tier in tiers) {
      if (tier.contains(subtotal)) return tier;
    }
    throw GcashFeeConfigException(
      'No GCash fee tier covers ${subtotal.format()}.',
    );
  }

  List<Map<String, Object?>> toJson() =>
      tiers.map((tier) => tier.toJson()).toList();

  /// Reads the table from Firestore, falling back to [defaultSchedule] when the document
  /// is missing so a new store is never left without a fee table.
  static GcashFeeSchedule fromJson(Object? value) {
    if (value is! List || value.isEmpty) return defaultSchedule;
    final tiers = value
        .whereType<Map<Object?, Object?>>()
        .map((raw) => GcashFeeTier.fromJson(raw.cast<String, Object?>()))
        .toList();
    return GcashFeeSchedule.validated(tiers);
  }

  @override
  bool operator ==(Object other) {
    if (other is! GcashFeeSchedule) return false;
    if (other.tiers.length != tiers.length) return false;
    for (var i = 0; i < tiers.length; i++) {
      if (other.tiers[i] != tiers[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(tiers);
}
