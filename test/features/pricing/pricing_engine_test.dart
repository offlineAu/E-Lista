import 'package:e_lista/core/money/money.dart';
import 'package:e_lista/core/money/percentage.dart';
import 'package:e_lista/features/pricing/domain/pricing_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const twentyPercent = Percentage.fromPercent(20);

  group('cash price — markup, rounded down to a whole peso', () {
    test('₱15 at 20% is ₱18', () {
      final price = PricingEngine.cashPrice(
        cost: const Money.fromPesos(15),
        markup: twentyPercent,
      );
      expect(price, const Money.fromPesos(18));
      expect(price.format(), '₱18');
    });

    test(
      '₱17 at 20% is ₱20 — ₱20.40 floors, it does not round to ₱20 by luck',
      () {
        final price = PricingEngine.cashPrice(
          cost: const Money.fromPesos(17),
          markup: twentyPercent,
        );
        expect(price, const Money.fromPesos(20));
      },
    );

    test('never rounds up, even at .99', () {
      // ₱17.49 at 20% is ₱20.988 — conventional rounding would give ₱21.
      final price = PricingEngine.cashPrice(
        cost: const Money.fromCentavos(1749),
        markup: twentyPercent,
      );
      expect(price, const Money.fromPesos(20));
    });

    test('a marked-up price just under a peso boundary floors down', () {
      // ₱16.666 at 20% is ₱19.9992: flooring the exact value gives ₱19. Rounding to the
      // nearest centavo first would give ₱20.00 and then wrongly stay at ₱20.
      final price = PricingEngine.cashPrice(
        cost: const Money.fromCentavos(1666),
        markup: twentyPercent,
      );
      expect(price, const Money.fromPesos(19));
    });

    test('the result is always whole pesos', () {
      for (var costCentavos = 1; costCentavos <= 5000; costCentavos++) {
        final price = PricingEngine.cashPrice(
          cost: Money.fromCentavos(costCentavos),
          markup: const Percentage.fromBasisPoints(1750),
        );
        expect(price.isWholePesos, isTrue, reason: 'cost $costCentavos');
      }
    });

    test('a fractional percentage stays exact', () {
      // ₱15 at 17.5% is ₱17.625 → ₱17.
      final price = PricingEngine.cashPrice(
        cost: const Money.fromPesos(15),
        markup: const Percentage.fromBasisPoints(1750),
      );
      expect(price, const Money.fromPesos(17));
    });

    test('zero markup sells at cost, floored', () {
      expect(
        PricingEngine.cashPrice(
          cost: const Money.fromCentavos(1875),
          markup: Percentage.zero,
        ),
        const Money.fromPesos(18),
      );
    });

    test('rejects a negative cost or markup', () {
      expect(
        () => PricingEngine.cashPrice(
          cost: const Money.fromCentavos(-1),
          markup: twentyPercent,
        ),
        throwsA(isA<PricingException>()),
      );
      expect(
        () => PricingEngine.cashPrice(
          cost: const Money.fromPesos(15),
          markup: const Percentage.fromBasisPoints(-100),
        ),
        throwsA(isA<PricingException>()),
      );
    });
  });

  group('GCash price — same markup as cash, floored to a whole peso', () {
    test('₱15 at 20% is ₱18', () {
      final price = PricingEngine.gcashBasePrice(
        cost: const Money.fromPesos(15),
        markup: twentyPercent,
      );
      expect(price, const Money.fromPesos(18));
      expect(price.format(), '₱18');
    });

    test('is always identical to the cash price for the same cost', () {
      for (var costCentavos = 100;
          costCentavos <= 20000;
          costCentavos += 37) {
        final cost = Money.fromCentavos(costCentavos);
        final cash = PricingEngine.cashPrice(cost: cost, markup: twentyPercent);
        final gcash = PricingEngine.gcashBasePrice(
          cost: cost,
          markup: twentyPercent,
        );
        expect(gcash, cash, reason: 'cost ${cost.format()}');
      }
    });

    test('zero markup sells at cost, floored', () {
      expect(
        PricingEngine.gcashBasePrice(
          cost: const Money.fromCentavos(1875),
          markup: Percentage.zero,
        ),
        const Money.fromPesos(18),
      );
    });

    test('rejects a negative cost or markup', () {
      expect(
        () => PricingEngine.gcashBasePrice(
          cost: const Money.fromCentavos(-1),
          markup: twentyPercent,
        ),
        throwsA(isA<PricingException>()),
      );
    });
  });

  group('pricesFor', () {
    test('derives both prices from one profit percentage', () {
      final prices = PricingEngine.pricesFor(
        cost: const Money.fromPesos(15),
        profitPercentage: twentyPercent,
      );
      expect(prices.cash, const Money.fromPesos(18));
      expect(prices.gcashBase, const Money.fromPesos(18));
    });
  });

  group('effective profit percentage', () {
    const storeDefault = Percentage.fromPercent(20);
    const productCustom = Percentage.fromPercent(15);

    test('a standard product follows the store default', () {
      expect(
        PricingEngine.effectiveProfitPercentage(
          mode: PricingMode.standard,
          productPercentage: productCustom,
          storeDefault: storeDefault,
        ),
        storeDefault,
        reason: 'a stale custom value must not leak into a standard product',
      );
    });

    test('a custom product keeps its own percentage', () {
      expect(
        PricingEngine.effectiveProfitPercentage(
          mode: PricingMode.custom,
          productPercentage: productCustom,
          storeDefault: storeDefault,
        ),
        productCustom,
      );
    });

    test(
      'a custom product with no percentage set falls back to the default',
      () {
        expect(
          PricingEngine.effectiveProfitPercentage(
            mode: PricingMode.custom,
            productPercentage: null,
            storeDefault: storeDefault,
          ),
          storeDefault,
        );
      },
    );

    test('raising the store default re-prices standard products only', () {
      // Piattos follows the store default; Coke is fixed at 15%. Both cost ₱20.
      const cost = Money.fromPesos(20);

      Money cashFor(
        PricingMode mode,
        Percentage? custom,
        Percentage storeDefault,
      ) {
        return PricingEngine.cashPrice(
          cost: cost,
          markup: PricingEngine.effectiveProfitPercentage(
            mode: mode,
            productPercentage: custom,
            storeDefault: storeDefault,
          ),
        );
      }

      final piattosBefore = cashFor(PricingMode.standard, null, storeDefault);
      final cokeBefore = cashFor(
        PricingMode.custom,
        productCustom,
        storeDefault,
      );
      expect(piattosBefore, const Money.fromPesos(24)); // ₱20 + 20%
      expect(cokeBefore, const Money.fromPesos(23)); // ₱20 + 15%

      const raised = Percentage.fromPercent(25);
      expect(
        cashFor(PricingMode.standard, null, raised),
        const Money.fromPesos(25),
      );
      expect(
        cashFor(PricingMode.custom, productCustom, raised),
        cokeBefore,
        reason: 'a custom product must not move when the store default changes',
      );
    });
  });

  group('PricingMode serialisation', () {
    test('round-trips and defaults to standard for unknown values', () {
      expect(PricingMode.fromJson('custom'), PricingMode.custom);
      expect(PricingMode.fromJson('standard'), PricingMode.standard);
      expect(PricingMode.fromJson(null), PricingMode.standard);
      expect(PricingMode.fromJson('nonsense'), PricingMode.standard);
      expect(PricingMode.custom.toJson(), 'custom');
    });
  });

  group('per-unit profit', () {
    test('cash profit is price minus cost', () {
      expect(
        PricingEngine.cashProfitPerUnit(
          cost: const Money.fromPesos(15),
          cashPrice: const Money.fromPesos(18),
        ),
        const Money.fromPesos(3),
      );
    });

    test(
      'GCash profit excludes the convenience fee, which is per transaction',
      () {
        expect(
          PricingEngine.gcashProfitPerUnit(
            cost: const Money.fromPesos(15),
            gcashPrice: const Money.fromPesos(18),
          ),
          const Money.fromPesos(3),
        );
      },
    );
  });
}
