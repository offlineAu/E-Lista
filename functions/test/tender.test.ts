import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { resolveCashTender, resolveTender, TenderError } from '../src/domain/tender';

describe('resolveCashTender', () => {
  it('tendered exactly equal to the total leaves no change', () => {
    assert.deepEqual(resolveCashTender(15000, 15000), {
      amountTenderedCentavos: 15000,
      changeCentavos: 0,
    });
  });

  it('tendered more than the total returns the difference as change', () => {
    assert.deepEqual(resolveCashTender(15000, 20000), {
      amountTenderedCentavos: 20000,
      changeCentavos: 5000,
    });
  });

  it('tendered less than the total is refused', () => {
    assert.throws(() => resolveCashTender(15000, 14999), TenderError);
  });

  it('a negative tendered amount is refused', () => {
    assert.throws(() => resolveCashTender(15000, -1), TenderError);
  });

  it('a non-integer tendered amount is refused', () => {
    assert.throws(() => resolveCashTender(15000, 15000.5), TenderError);
  });

  it('a zero total accepts a zero tender', () => {
    assert.deepEqual(resolveCashTender(0, 0), {
      amountTenderedCentavos: 0,
      changeCentavos: 0,
    });
  });
});

describe('resolveTender', () => {
  it('cash defers to resolveCashTender', () => {
    assert.deepEqual(
      resolveTender({ paymentMethod: 'cash', totalCentavos: 15000, amountTenderedCentavos: 20000 }),
      { amountTenderedCentavos: 20000, changeCentavos: 5000 },
    );
  });

  it('cash with no tendered amount is refused', () => {
    assert.throws(
      () => resolveTender({ paymentMethod: 'cash', totalCentavos: 15000 }),
      TenderError,
    );
  });

  it('gcash always resolves to no tender and no change', () => {
    assert.deepEqual(resolveTender({ paymentMethod: 'gcash', totalCentavos: 15000 }), {
      amountTenderedCentavos: null,
      changeCentavos: null,
    });
  });

  it('gcash ignores a stray tendered amount rather than rejecting it', () => {
    assert.deepEqual(
      resolveTender({ paymentMethod: 'gcash', totalCentavos: 15000, amountTenderedCentavos: 1 }),
      { amountTenderedCentavos: null, changeCentavos: null },
    );
  });
});
