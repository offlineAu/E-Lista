import 'package:meta/meta.dart';

/// Thrown when a monetary value or operation is not representable.
class MoneyException implements Exception {
  const MoneyException(this.message);

  final String message;

  @override
  String toString() => 'MoneyException: $message';
}

/// An exact amount of Philippine pesos, stored as a whole number of centavos.
///
/// Every peso value in E-Lista — prices, costs, order totals, GCash fees, sales figures —
/// is a [Money]. Doubles are never used for money: `0.1 + 0.2` is not `0.3` in binary
/// floating point, and a store that is a centavo out on every GCash order notices. Storing
/// centavos as an `int` makes addition, subtraction and multiplication by a quantity exact,
/// and forces every division to state its rounding rule explicitly.
///
/// The centavo count stays well inside the 53-bit range that `int` guarantees on the web,
/// so the same arithmetic holds on every platform: intermediate products in the pricing
/// engine reach at most `centavos × 10000`, which is under 2^53 for any amount below
/// ₱9 billion.
@immutable
class Money implements Comparable<Money> {
  const Money._(this.centavos);

  /// An amount given directly in centavos. `Money.fromCentavos(1875)` is ₱18.75.
  const Money.fromCentavos(this.centavos);

  /// An amount given in whole pesos. `Money.fromPesos(18)` is ₱18.00.
  const Money.fromPesos(int pesos) : centavos = pesos * centavosPerPeso;

  /// Zero pesos.
  static const Money zero = Money._(0);

  /// Centavos in one peso.
  static const int centavosPerPeso = 100;

  /// The exact amount, in centavos. Negative values are permitted so that differences and
  /// inventory-value corrections can be expressed.
  final int centavos;

  /// Parses user input such as `18`, `18.5`, `18.75`, `₱18.75` or `1,234.50`.
  ///
  /// Returns `null` when [input] is not a well-formed amount, so callers can turn it into
  /// a field-level validation message rather than an exception.
  static Money? tryParse(String input) {
    final cleaned = input.trim().replaceAll('₱', '').replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;

    final match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;

    final negative = match.group(1) != null;
    final pesos = int.tryParse(match.group(2)!);
    if (pesos == null) return null;

    final fraction = match.group(3);
    final centavoPart = fraction == null
        ? 0
        : int.parse(fraction.padRight(2, '0'));

    final total = pesos * centavosPerPeso + centavoPart;
    return Money.fromCentavos(negative ? -total : total);
  }

  bool get isZero => centavos == 0;
  bool get isNegative => centavos < 0;
  bool get isPositive => centavos > 0;

  /// True when the amount is an exact number of pesos, e.g. ₱18 but not ₱18.75.
  bool get isWholePesos => centavos % centavosPerPeso == 0;

  Money operator +(Money other) =>
      Money.fromCentavos(centavos + other.centavos);

  Money operator -(Money other) =>
      Money.fromCentavos(centavos - other.centavos);

  Money operator -() => Money.fromCentavos(-centavos);

  /// Repeats the amount [quantity] times — a line total. Exact by construction.
  Money operator *(int quantity) => Money.fromCentavos(centavos * quantity);

  bool operator <(Money other) => centavos < other.centavos;
  bool operator <=(Money other) => centavos <= other.centavos;
  bool operator >(Money other) => centavos > other.centavos;
  bool operator >=(Money other) => centavos >= other.centavos;

  /// The amount rounded **down** to a whole peso: ₱20.99, ₱20.50 and ₱20.01 all give ₱20.
  ///
  /// Rounding is towards negative infinity, not towards zero, so the rule stays consistent
  /// for the negative amounts that appear in refunds and adjustments.
  Money floorToPeso() {
    final pesos = _floorDiv(centavos, centavosPerPeso);
    return Money.fromCentavos(pesos * centavosPerPeso);
  }

  /// Sums a sequence of amounts; an empty sequence gives [zero].
  static Money sum(Iterable<Money> amounts) =>
      amounts.fold(Money.zero, (total, amount) => total + amount);

  /// Formats for display: `₱18.75`, and `₱18` when the amount is whole pesos.
  ///
  /// Cash prices are always whole pesos and read naturally as `₱18`; GCash prices keep
  /// their centavos. A floating-point artifact such as `₱18.749999999` cannot be produced
  /// by this type.
  String format() => _format(alwaysShowCentavos: false);

  /// Formats with centavos always shown: `₱18.00`. Used in tables where a column of
  /// amounts should align on the decimal point.
  String formatExact() => _format(alwaysShowCentavos: true);

  String _format({required bool alwaysShowCentavos}) {
    final absolute = centavos.abs();
    final pesos = absolute ~/ centavosPerPeso;
    final remainder = absolute % centavosPerPeso;

    final grouped = _groupThousands(pesos);
    final body = (remainder == 0 && !alwaysShowCentavos)
        ? grouped
        : '$grouped.${remainder.toString().padLeft(2, '0')}';

    return '${centavos < 0 ? '-' : ''}₱$body';
  }

  static String _groupThousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// The value as stored in Firestore: a plain integer of centavos.
  int toJson() => centavos;

  /// Reads a Firestore value that should be centavos.
  ///
  /// Legacy or hand-edited documents may hold a double; those are accepted and rounded to
  /// the nearest centavo rather than crashing the catalog for every customer.
  static Money fromJson(Object? value) {
    if (value == null) return Money.zero;
    if (value is int) return Money.fromCentavos(value);
    if (value is double) return Money.fromCentavos(value.round());
    if (value is num) return Money.fromCentavos(value.round());
    if (value is String) {
      final parsed = Money.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw MoneyException('Cannot read $value as an amount in centavos.');
  }

  @override
  int compareTo(Money other) => centavos.compareTo(other.centavos);

  @override
  bool operator ==(Object other) =>
      other is Money && other.centavos == centavos;

  @override
  int get hashCode => centavos.hashCode;

  @override
  String toString() => format();
}

/// Integer division rounding towards negative infinity.
int _floorDiv(int numerator, int denominator) {
  final quotient = numerator ~/ denominator;
  final hasRemainder = numerator % denominator != 0;
  final oppositeSigns = (numerator < 0) != (denominator < 0);
  return (hasRemainder && oppositeSigns) ? quotient - 1 : quotient;
}
