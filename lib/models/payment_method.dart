import '../core/money/money.dart';
import 'product.dart';

/// How an order is paid for.
///
/// Adding a method later — Maya, bank transfer, store credit — means adding a value here
/// and answering the three questions this enum asks: which price list it uses, whether it
/// carries a per-transaction convenience fee, and what to call it. Nothing else in the app
/// branches on the payment method, so a new one cannot be half-implemented: the compiler
/// flags every exhaustive `switch` that has not been updated.
enum PaymentMethod {
  /// Cash on pickup or delivery. Uses the marked-up, whole-peso cash price.
  cash(
    id: 'cash',
    label: 'Cash',
    description: 'Pay with cash when you get your order.',
    chargesConvenienceFee: false,
  ),

  /// GCash transfer. Uses the true-margin price and adds one convenience fee per order.
  gcash(
    id: 'gcash',
    label: 'GCash',
    description:
        'Pay by GCash transfer. A small convenience fee applies per order.',
    chargesConvenienceFee: true,
  );

  const PaymentMethod({
    required this.id,
    required this.label,
    required this.description,
    required this.chargesConvenienceFee,
  });

  /// Stable identifier written to Firestore. Never rename an existing one — historical
  /// orders are read back by it.
  final String id;

  /// What the customer sees on the payment selector.
  final String label;

  /// One line explaining the method at checkout.
  final String description;

  /// Whether a once-per-transaction fee is added on top of the subtotal.
  ///
  /// The fee is per *order*, never per product, and its amount comes from the owner's
  /// configurable tier table.
  final bool chargesConvenienceFee;

  /// The per-unit price this method charges for [product].
  ///
  /// This is the single place the cash/GCash price lists are chosen between, which is why
  /// no screen needs to know that GCash prices are the ones with centavos.
  Money unitPrice(Product product) => switch (this) {
    PaymentMethod.cash => product.cashPrice,
    PaymentMethod.gcash => product.gcashBasePrice,
  };

  static PaymentMethod fromJson(Object? value) => switch (value) {
    'gcash' => PaymentMethod.gcash,
    'cash' => PaymentMethod.cash,
    // An order written by a newer build with a method this build does not know about
    // must not crash order history. Cash is the conservative reading: it never invents
    // a convenience fee that was not charged.
    _ => PaymentMethod.cash,
  };

  String toJson() => id;
}
