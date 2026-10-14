import 'package:meta/meta.dart';

/// Thrown when a percentage is outside the range a setting allows.
class PercentageException implements Exception {
  const PercentageException(this.message);

  final String message;

  @override
  String toString() => 'PercentageException: $message';
}

/// An exact percentage, stored as a whole number of basis points.
///
/// One basis point is 0.01%, so 20% is 2000 bp and 20.5% is 2050 bp. Owners routinely set
/// profit percentages with one decimal place; holding them as `double` would reintroduce
/// the rounding drift that `Money` exists to avoid, because the percentage is a factor in
/// every price the store quotes.
///
/// Two decimal places is the configured limit — finer than that has no effect on a price
/// quoted in centavos.
@immutable
class Percentage implements Comparable<Percentage> {
  const Percentage.fromBasisPoints(this.basisPoints);

  /// A whole-number percentage: `Percentage.fromPercent(20)` is 20%.
  const Percentage.fromPercent(int percent)
    : basisPoints = percent * basisPointsPerPercent;

  static const Percentage zero = Percentage.fromBasisPoints(0);

  /// Basis points in one percent.
  static const int basisPointsPerPercent = 100;

  /// Basis points in the whole (100%).
  static const int basisPointsPerUnit = 10000;

  /// The percentage in basis points. 20% is `2000`.
  final int basisPoints;

  /// Parses owner input such as `20`, `20.5`, `20.50` or `20%`.
  ///
  /// Returns `null` for anything malformed so the caller can show a validation message.
  static Percentage? tryParse(String input) {
    final cleaned = input.trim().replaceAll('%', '').trim();
    if (cleaned.isEmpty) return null;

    final match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;

    final negative = match.group(1) != null;
    final whole = int.tryParse(match.group(2)!);
    if (whole == null) return null;

    final fraction = match.group(3);
    final fractionPart = fraction == null
        ? 0
        : int.parse(fraction.padRight(2, '0'));

    final total = whole * basisPointsPerPercent + fractionPart;
    return Percentage.fromBasisPoints(negative ? -total : total);
  }

  bool get isZero => basisPoints == 0;
  bool get isNegative => basisPoints < 0;

  /// True when the percentage is 100% or more — a markup that doubles the price or more,
  /// which no pricing form should let an owner reach unnoticed.
  bool get isAtLeastWhole => basisPoints >= basisPointsPerUnit;

  /// Formats for display: `20%`, `20.5%`, `20.25%`.
  String format() {
    final absolute = basisPoints.abs();
    final whole = absolute ~/ basisPointsPerPercent;
    final fraction = absolute % basisPointsPerPercent;

    final body = switch (fraction) {
      0 => '$whole',
      _ when fraction % 10 == 0 => '$whole.${fraction ~/ 10}',
      _ => '$whole.${fraction.toString().padLeft(2, '0')}',
    };

    return '${basisPoints < 0 ? '-' : ''}$body%';
  }

  /// The value as stored in Firestore: a plain integer of basis points.
  int toJson() => basisPoints;

  /// Reads a Firestore value that should be basis points.
  ///
  /// A `double` is accepted and rounded, so a document written by hand as `20.0` still
  /// loads instead of breaking pricing for that product.
  static Percentage fromJson(Object? value) {
    if (value == null) return Percentage.zero;
    if (value is int) return Percentage.fromBasisPoints(value);
    if (value is num) return Percentage.fromBasisPoints(value.round());
    if (value is String) {
      final parsed = Percentage.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw PercentageException(
      'Cannot read $value as a percentage in basis points.',
    );
  }

  @override
  int compareTo(Percentage other) => basisPoints.compareTo(other.basisPoints);

  @override
  bool operator ==(Object other) =>
      other is Percentage && other.basisPoints == basisPoints;

  @override
  int get hashCode => basisPoints.hashCode;

  @override
  String toString() => format();
}
