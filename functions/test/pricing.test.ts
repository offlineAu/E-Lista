import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  cashPriceCentavos,
  formatCentavos,
  gcashBasePriceCentavos,
  divideRoundHalfUp,
  MoneyError,
} from '../src/domain/money';
import {
  DEFAULT_GCASH_FEE_TIERS,
  GcashFeeConfigError,
  normaliseGcashFeeTiers,
  resolveGcashFeeCentavos,
} from '../src/domain/gcash_fees';

const TWENTY_PERCENT = 2000;

describe('cash price', () => {
  it('marks up and floors to a whole peso', () => {
    assert.equal(cashPriceCentavos(1500, TWENTY_PERCENT), 1800); // ₱15 → ₱18
    assert.equal(cashPriceCentavos(1700, TWENTY_PERCENT), 2000); // ₱17 → ₱20.40 → ₱20
    assert.equal(cashPriceCentavos(1749, TWENTY_PERCENT), 2000); // ₱20.988 → ₱20
    assert.equal(cashPriceCentavos(1666, TWENTY_PERCENT), 1900); // ₱19.992 → ₱19
  });

  it('always yields whole pesos', () => {
    for (let cost = 1; cost <= 5000; cost++) {
      assert.equal(cashPriceCentavos(cost, 1750) % 100, 0);
    }
  });

  it('rejects negative inputs', () => {
    assert.throws(() => cashPriceCentavos(-1, TWENTY_PERCENT), MoneyError);
    assert.throws(() => cashPriceCentavos(1500, -1), MoneyError);
  });
});

describe('GCash base price', () => {
  it('uses a true margin and keeps centavos', () => {
    assert.equal(gcashBasePriceCentavos(1500, TWENTY_PERCENT), 1875); // ₱18.75
    assert.equal(gcashBasePriceCentavos(1700, TWENTY_PERCENT), 2125); // ₱21.25
    assert.equal(gcashBasePriceCentavos(1000, 3000), 1429); // ₱14.2857… → ₱14.29
  });

  it('makes the margin a share of the selling price', () => {
    const price = gcashBasePriceCentavos(1500, TWENTY_PERCENT);
    assert.equal(price - 1500, 375); // 20% of ₱18.75, not 20% of ₱15
  });

  it('rejects a margin of 100% or more', () => {
    assert.throws(() => gcashBasePriceCentavos(1500, 10000), MoneyError);
    assert.throws(() => gcashBasePriceCentavos(1500, 15000), MoneyError);
  });
});

describe('parity with the Dart pricing engine', () => {
  // These are the same cases asserted in test/features/pricing/pricing_engine_test.dart.
  // The client previews a price and the server charges it; if the two ever disagree, a
  // customer sees one number and pays another.
  const cases: Array<[number, number, number, number]> = [
    [1500, 2000, 1800, 1875],
    [1700, 2000, 2000, 2125],
    [1749, 2000, 2000, 2186],
    [1666, 2000, 1900, 2083],
    [1500, 1750, 1700, 1818],
    [1000, 3000, 1300, 1429],
    [1500, 0, 1500, 1500],
  ];

  for (const [cost, bp, expectedCash, expectedGcash] of cases) {
    it(`cost ${formatCentavos(cost)} at ${bp / 100}%`, () => {
      assert.equal(cashPriceCentavos(cost, bp), expectedCash);
      assert.equal(gcashBasePriceCentavos(cost, bp), expectedGcash);
    });
  }
});

describe('GCash fee tiers', () => {
  const tiers = normaliseGcashFeeTiers(DEFAULT_GCASH_FEE_TIERS);

  it('resolves every documented boundary', () => {
    const expectations: Array<[number, number]> = [
      [0, 50],
      [9999, 50],
      [10000, 100],
      [29999, 100],
      [30000, 200],
      [49999, 200],
      [50000, 300],
      [99999, 300],
      [100000, 500],
      [100001, 500],
      [5000000, 500],
    ];
    for (const [subtotal, fee] of expectations) {
      assert.equal(
        resolveGcashFeeCentavos(subtotal, tiers),
        fee,
        `subtotal ${formatCentavos(subtotal)}`,
      );
    }
  });

  it('charges the fee once per transaction', () => {
    const subtotal = 1875 * 2 + 2500; // ₱62.50
    assert.equal(subtotal, 6250);
    assert.equal(subtotal + resolveGcashFeeCentavos(subtotal, tiers), 6300);
  });

  it('rejects overlaps, gaps and bad ranges', () => {
    assert.throws(
      () =>
        normaliseGcashFeeTiers([
          { minCentavos: 0, maxCentavos: 10000, feeCentavos: 50 },
          { minCentavos: 9000, maxCentavos: null, feeCentavos: 100 },
        ]),
      GcashFeeConfigError,
    );
    assert.throws(
      () =>
        normaliseGcashFeeTiers([
          { minCentavos: 0, maxCentavos: 9999, feeCentavos: 50 },
          { minCentavos: 20000, maxCentavos: null, feeCentavos: 100 },
        ]),
      GcashFeeConfigError,
    );
    assert.throws(
      () => normaliseGcashFeeTiers([{ minCentavos: 0, maxCentavos: 9999, feeCentavos: 50 }]),
      GcashFeeConfigError,
    );
    assert.throws(
      () => normaliseGcashFeeTiers([{ minCentavos: 100, maxCentavos: null, feeCentavos: 50 }]),
      GcashFeeConfigError,
    );
    assert.throws(
      () => normaliseGcashFeeTiers([{ minCentavos: 0, maxCentavos: null, feeCentavos: -1 }]),
      GcashFeeConfigError,
    );
    assert.throws(() => normaliseGcashFeeTiers([]), GcashFeeConfigError);
  });

  it('sorts tiers given out of order', () => {
    const sorted = normaliseGcashFeeTiers([
      { minCentavos: 10000, maxCentavos: null, feeCentavos: 100 },
      { minCentavos: 0, maxCentavos: 9999, feeCentavos: 50 },
    ]);
    assert.equal(sorted[0].minCentavos, 0);
  });
});

describe('formatting and rounding helpers', () => {
  it('formats centavos the way the app does', () => {
    assert.equal(formatCentavos(1800), '₱18');
    assert.equal(formatCentavos(1875), '₱18.75');
    assert.equal(formatCentavos(50), '₱0.50');
    assert.equal(formatCentavos(-525), '-₱5.25');
  });

  it('rounds halves away from zero', () => {
    assert.equal(divideRoundHalfUp(5, 2), 3);
    assert.equal(divideRoundHalfUp(-5, 2), -3);
    assert.equal(divideRoundHalfUp(1, 3), 0);
    assert.throws(() => divideRoundHalfUp(1, 0), MoneyError);
  });
});
