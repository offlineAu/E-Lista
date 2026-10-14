import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { CashCountError, resolveCashCount } from '../src/domain/cash_count';

describe('resolveCashCount', () => {
  it('counted matching expected has no difference', () => {
    assert.deepEqual(
      resolveCashCount({ expectedCentavos: 15000, countedCentavos: 15000 }),
      { expectedCentavos: 15000, countedCentavos: 15000, differenceCentavos: 0 },
    );
  });

  it('counted more than expected is a positive difference — over', () => {
    assert.deepEqual(
      resolveCashCount({ expectedCentavos: 15000, countedCentavos: 15500 }),
      { expectedCentavos: 15000, countedCentavos: 15500, differenceCentavos: 500 },
    );
  });

  it('counted less than expected is a negative difference — short', () => {
    assert.deepEqual(
      resolveCashCount({ expectedCentavos: 15000, countedCentavos: 14000 }),
      { expectedCentavos: 15000, countedCentavos: 14000, differenceCentavos: -1000 },
    );
  });

  it('a zero expected amount accepts a zero count', () => {
    assert.deepEqual(
      resolveCashCount({ expectedCentavos: 0, countedCentavos: 0 }),
      { expectedCentavos: 0, countedCentavos: 0, differenceCentavos: 0 },
    );
  });

  it('a negative expected amount is refused', () => {
    assert.throws(
      () => resolveCashCount({ expectedCentavos: -1, countedCentavos: 0 }),
      CashCountError,
    );
  });

  it('a negative counted amount is refused', () => {
    assert.throws(
      () => resolveCashCount({ expectedCentavos: 0, countedCentavos: -1 }),
      CashCountError,
    );
  });

  it('a non-integer counted amount is refused', () => {
    assert.throws(
      () => resolveCashCount({ expectedCentavos: 15000, countedCentavos: 15000.5 }),
      CashCountError,
    );
  });
});
