import '../money/money.dart';
import '../money/percentage.dart';

/// Form validation, in one place.
///
/// Every validator returns `null` when the value is acceptable and a sentence when it is
/// not — the shape `TextFormField.validator` wants. Keeping them here rather than inline
/// means the rule for a cost price is the same on the add-product screen, the edit screen
/// and the restock sheet, and that the wording stays consistent.
abstract final class Validators {
  // ------------------------------------------------------------------ text

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required.';
    return null;
  }

  static String? productName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Give the product a name.';
    if (name.length < 2) return 'That name is too short.';
    if (name.length > 120) return 'Keep the name under 120 characters.';
    return null;
  }

  static String? personName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Please enter your name.';
    if (name.length < 2) return 'Please enter your full name.';
    return null;
  }

  // --------------------------------------------------------------- accounts

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter your email.';
    // Deliberately permissive: the authoritative check is Firebase's, and rejecting a
    // valid-but-unusual address here would lock someone out of their own store.
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'That email address does not look right.';
    }
    return null;
  }

  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Please choose a password.';
    if (password.length < 8) {
      return 'Use at least 8 characters.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value != original) return 'The passwords do not match.';
    return null;
  }

  /// A Philippine mobile or landline number.
  ///
  /// Accepts `09171234567`, `+639171234567` and `(02) 8123 4567`, because those are all
  /// things people actually type. Only the digits are checked.
  static String? phoneNumber(String? value, {bool isRequired = true}) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return isRequired ? 'Please enter a contact number.' : null;
    }

    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return 'That number looks too short.';
    if (digits.length > 15) return 'That number looks too long.';
    return null;
  }

  // ------------------------------------------------------------------ money

  /// A cost or price the owner typed.
  ///
  /// [allowZero] is on for cost, because a free promotional item genuinely costs nothing,
  /// and off wherever a zero would be a mistake.
  static String? money(
    String? value, {
    String field = 'Amount',
    bool allowZero = true,
    Money? maximum,
  }) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return '$field is required.';

    final amount = Money.tryParse(raw);
    if (amount == null) {
      return 'Enter $field as a number, for example 15 or 15.50.';
    }
    if (amount.isNegative) return '$field cannot be negative.';
    if (!allowZero && amount.isZero) return '$field must be more than ₱0.';
    if (maximum != null && amount > maximum) {
      return '$field cannot be more than ${maximum.format()}.';
    }
    return null;
  }

  static String? costPrice(String? value) => money(
    value,
    field: 'Cost price',
    maximum: const Money.fromPesos(1000000),
  );

  // ------------------------------------------------------------- percentage

  /// A profit percentage.
  ///
  /// The ceiling is not arbitrary: GCash pricing divides by `1 - margin`, so a percentage
  /// at or near 100% produces a price no one would ever charge.
  static String? profitPercentage(
    String? value, {
    int maximumBasisPoints = 9000,
  }) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Enter a profit percentage.';

    final percentage = Percentage.tryParse(raw);
    if (percentage == null) {
      return 'Enter a percentage, for example 20 or 20.5.';
    }
    if (percentage.isNegative) return 'Profit cannot be negative.';
    if (percentage.basisPoints >= maximumBasisPoints) {
      final maximum = Percentage.fromBasisPoints(maximumBasisPoints);
      return 'Profit must be below ${maximum.format()}.';
    }
    return null;
  }

  // ------------------------------------------------------------- quantities

  static String? stockQuantity(
    String? value, {
    String field = 'Stock',
    bool allowNegative = false,
    int maximum = 1000000,
  }) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return '$field is required.';

    final quantity = int.tryParse(raw);
    if (quantity == null) return 'Enter $field as a whole number.';
    if (!allowNegative && quantity < 0) return '$field cannot be negative.';
    if (quantity.abs() > maximum) return 'That $field looks too large.';
    return null;
  }

  /// A quantity being added or removed in an inventory movement, which must not be zero —
  /// a movement of nothing is not a movement.
  static String? movementQuantity(String? value, {bool allowNegative = false}) {
    final base = stockQuantity(
      value,
      field: 'Quantity',
      allowNegative: allowNegative,
    );
    if (base != null) return base;
    if (int.parse(value!.trim()) == 0) {
      return 'Enter a quantity other than zero.';
    }
    return null;
  }

  static String? lowStockThreshold(String? value) =>
      stockQuantity(value, field: 'Low stock alert', maximum: 100000);

  static String? orderQuantity(String? value, {required int availableStock}) {
    final raw = value?.trim() ?? '';
    final quantity = int.tryParse(raw);
    if (quantity == null) return 'Enter a whole number.';
    if (quantity < 1) return 'Order at least one.';
    if (quantity > availableStock) {
      return availableStock <= 0
          ? 'This is out of stock.'
          : 'Only $availableStock left.';
    }
    return null;
  }

  // --------------------------------------------------------------- barcodes

  /// A scanned or typed barcode.
  ///
  /// Real retail barcodes are 8–14 digits (EAN-8, UPC-A, EAN-13, ITF-14). Anything else is
  /// almost certainly a misread, and accepting it would create a product that can never be
  /// found by scanning again.
  static String? barcode(String? value, {bool isRequired = false}) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return isRequired ? 'Scan or enter a barcode.' : null;
    }
    if (!RegExp(r'^\d+$').hasMatch(raw)) {
      return 'A barcode is digits only.';
    }
    if (raw.length < 8 || raw.length > 14) {
      return 'A barcode is 8 to 14 digits long.';
    }
    return null;
  }

  /// Whether a barcode is well-formed, for code that needs a boolean rather than a message.
  static bool isValidBarcode(String value) => barcode(value) == null;

  // ------------------------------------------------------------------ units

  /// How a product is sold. Free text, but not empty and not an essay.
  static String? unit(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Enter a unit, for example pc, pack or sachet.';
    if (raw.length > 16) {
      return 'Keep the unit short, for example pc or sachet.';
    }
    return null;
  }

  /// The units a sari-sari store actually uses, offered as suggestions.
  static const List<String> commonUnits = [
    'pc',
    'pack',
    'sachet',
    'bottle',
    'can',
    'box',
    'kg',
    'g',
    'L',
    'mL',
    'tie',
    'bundle',
  ];
}
