import '../../../core/money/money.dart';
import '../../../core/money/percentage.dart';

/// Whether a product prices itself from the store-wide profit percentage or from its own.
enum PricingMode {
  /// Follow `settings/pricing.defaultProfitPercentage`. Changing the store-wide figure
  /// re-prices every product in this mode.
  standard,

  /// Use the product's own `profitPercentage` and ignore the store-wide figure.
  custom;

  static PricingMode fromJson(Object? value) => switch (value) {
    'custom' => PricingMode.custom,
    _ => PricingMode.standard,
  };

  String toJson() => name;

  String get label => switch (this) {
    PricingMode.standard => 'Store default',
    PricingMode.custom => 'Custom for this product',
  };
}

/// Raised when a pricing input cannot produce a sensible price.
class PricingException implements Exception {
  const PricingException(this.message);

  final String message;

  @override
  String toString() => 'PricingException: $message';
}

/// The pair of prices a product is sold at.
class ProductPrices {
  const ProductPrices({required this.cash, required this.gcashBase});

  /// What a cash customer pays per unit — always a whole number of pesos.
  final Money cash;

  /// What a GCash customer pays per unit, before the once-per-transaction convenience
  /// fee. Keeps its centavos.
  final Money gcashBase;

  @override
  String toString() => 'ProductPrices(cash: $cash, gcash: $gcashBase)';
}

/// Derives selling prices from the owner's receipt cost and profit percentage.
///
/// Cash and GCash use the same formula — a markup added on top of cost, then rounded
/// *down* to a whole peso, because a sari-sari store quotes prices in coins and a price
/// of ₱20.40 cannot be collected. The GCash convenience fee is then applied per
/// transaction, not per product.
///
/// At 20% on a ₱15 cost both methods give ₱18: ₱15 × 1.20, floored, with ₱3 of profit
/// (20% of cost).
///
/// Every method is pure and works on [Money]/[Percentage], so the results are exact and
/// the same logic is unit-tested without Firebase. `functions/src/domain/money.ts` mirrors
/// it on the server, which is the authority at checkout.
abstract final class PricingEngine {
  /// The cash selling price: `floor(cost × (1 + markup))`, rounded down to a whole peso.
  ///
  /// ₱15 at 20% gives ₱18. ₱17 at 20% gives ₱20.40, which becomes ₱20 — never ₱21, and
  /// never ₱20.40. Rounding is always down, never conventional rounding.
  static Money cashPrice({required Money cost, required Percentage markup}) {
    _assertCost(cost);
    _assertNotNegative(markup, 'Markup');

    // Floor straight from the exact rational rather than rounding to a centavo first:
    // a marked-up price of ₱19.999 must floor to ₱19, not round to ₱20.00 and stay there.
    final markedUp =
        cost.centavos * (Percentage.basisPointsPerUnit + markup.basisPoints);
    final wholePesos =
        markedUp ~/ (Percentage.basisPointsPerUnit * Money.centavosPerPeso);
    return Money.fromPesos(wholePesos);
  }

  /// The GCash base price — same markup formula as cash, rounded down to a whole peso.
  ///
  /// ₱15 at 20% gives ₱18. The GCash convenience fee is added per transaction on top of
  /// this, so per-product prices are identical whichever way the customer pays.
  static Money gcashBasePrice({
    required Money cost,
    required Percentage markup,
  }) {
    return cashPrice(cost: cost, markup: markup);
  }

  /// Both selling prices for a product.
  static ProductPrices pricesFor({
    required Money cost,
    required Percentage profitPercentage,
  }) {
    return ProductPrices(
      cash: cashPrice(cost: cost, markup: profitPercentage),
      gcashBase: gcashBasePrice(cost: cost, markup: profitPercentage),
    );
  }

  /// The percentage a product actually prices itself with.
  ///
  /// A product in [PricingMode.standard] follows the store-wide figure, so raising the
  /// store default from 20% to 25% re-prices it; a product in [PricingMode.custom] keeps
  /// its own figure and is unaffected.
  static Percentage effectiveProfitPercentage({
    required PricingMode mode,
    required Percentage? productPercentage,
    required Percentage storeDefault,
  }) {
    return switch (mode) {
      PricingMode.custom => productPercentage ?? storeDefault,
      PricingMode.standard => storeDefault,
    };
  }

  /// The profit earned on one cash unit: selling price minus cost.
  static Money cashProfitPerUnit({
    required Money cost,
    required Money cashPrice,
  }) => cashPrice - cost;

  /// The profit earned on one GCash unit, before the transaction's convenience fee. The
  /// fee is charged once per order, so it is subtracted at the order level, not here.
  static Money gcashProfitPerUnit({
    required Money cost,
    required Money gcashPrice,
  }) => gcashPrice - cost;

  static void _assertCost(Money cost) {
    if (cost.isNegative) {
      throw const PricingException('Cost price cannot be negative.');
    }
  }

  static void _assertNotNegative(Percentage percentage, String label) {
    if (percentage.isNegative) {
      throw PricingException('$label cannot be negative.');
    }
  }
}
