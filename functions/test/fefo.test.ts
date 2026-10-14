import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { allocateFefo, type BatchAvailability } from '../src/domain/fefo';

const NO_EXPIRY = 99999999999999; // sentinel used throughout these tests for "far future"

function batch(
  batchId: string,
  remainingQuantity: number,
  expiryDateMillis: number,
  unitCostCentavos = 1000,
): BatchAvailability {
  return { batchId, remainingQuantity, expiryDateMillis, unitCostCentavos };
}

describe('allocateFefo', () => {
  it('a single batch exactly covering the request draws it all from that batch', () => {
    const result = allocateFefo([batch('a', 10, 1)], 10);
    assert.deepEqual(result.draws, [{ batchId: 'a', quantity: 10, unitCostCentavos: 1000 }]);
    assert.equal(result.fulfilled, 10);
    assert.equal(result.shortfall, 0);
  });

  it('an exact match spans two batches, oldest-expiring first', () => {
    const result = allocateFefo(
      [batch('newer', 15, 2), batch('older', 10, 1)],
      25,
    );
    assert.deepEqual(result.draws, [
      { batchId: 'older', quantity: 10, unitCostCentavos: 1000 },
      { batchId: 'newer', quantity: 15, unitCostCentavos: 1000 },
    ]);
    assert.equal(result.fulfilled, 25);
    assert.equal(result.shortfall, 0);
  });

  it('a partial draw takes only what is needed from the second batch', () => {
    const result = allocateFefo([batch('a', 10, 1), batch('b', 20, 2)], 12);
    assert.deepEqual(result.draws, [
      { batchId: 'a', quantity: 10, unitCostCentavos: 1000 },
      { batchId: 'b', quantity: 2, unitCostCentavos: 1000 },
    ]);
    assert.equal(result.fulfilled, 12);
    assert.equal(result.shortfall, 0);
  });

  it('insufficient total stock draws everything available and reports a shortfall', () => {
    const result = allocateFefo([batch('a', 10, 1), batch('b', 20, 2)], 50);
    assert.deepEqual(result.draws, [
      { batchId: 'a', quantity: 10, unitCostCentavos: 1000 },
      { batchId: 'b', quantity: 20, unitCostCentavos: 1000 },
    ]);
    assert.equal(result.fulfilled, 30);
    assert.equal(result.shortfall, 20);
  });

  it('a depleted batch is skipped even with the earliest expiry', () => {
    const result = allocateFefo(
      [batch('earliest-but-empty', 0, 1), batch('later-but-has-stock', 5, 2)],
      5,
    );
    assert.deepEqual(result.draws, [
      { batchId: 'later-but-has-stock', quantity: 5, unitCostCentavos: 1000 },
    ]);
    assert.equal(result.shortfall, 0);
  });

  it('all batches depleted draws nothing and the whole request is a shortfall', () => {
    const result = allocateFefo([batch('a', 0, 1), batch('b', 0, 2)], 5);
    assert.deepEqual(result.draws, []);
    assert.equal(result.fulfilled, 0);
    assert.equal(result.shortfall, 5);
  });

  it('ties on expiry date break deterministically on batchId', () => {
    const result = allocateFefo(
      [batch('zzz', 5, 1), batch('aaa', 5, 1)],
      10,
    );
    assert.deepEqual(result.draws, [
      { batchId: 'aaa', quantity: 5, unitCostCentavos: 1000 },
      { batchId: 'zzz', quantity: 5, unitCostCentavos: 1000 },
    ]);
    // Running it again with the same input gives the same order — no hidden randomness.
    const again = allocateFefo([batch('zzz', 5, 1), batch('aaa', 5, 1)], 10);
    assert.deepEqual(again.draws, result.draws);
  });

  it('sorts unsorted input internally, drawing oldest-first regardless of array order', () => {
    const result = allocateFefo(
      [batch('newest', 5, 3), batch('oldest', 5, 1), batch('middle', 5, 2)],
      15,
    );
    assert.deepEqual(
      result.draws.map((d) => d.batchId),
      ['oldest', 'middle', 'newest'],
    );
  });

  it('a batch with no expiry sorts after everything that does expire', () => {
    const result = allocateFefo(
      [batch('no-expiry', 5, NO_EXPIRY), batch('expires-soon', 5, 1)],
      6,
    );
    assert.deepEqual(result.draws, [
      { batchId: 'expires-soon', quantity: 5, unitCostCentavos: 1000 },
      { batchId: 'no-expiry', quantity: 1, unitCostCentavos: 1000 },
    ]);
  });

  it('quantityNeeded of zero draws nothing and does not throw', () => {
    const result = allocateFefo([batch('a', 10, 1)], 0);
    assert.deepEqual(result.draws, []);
    assert.equal(result.fulfilled, 0);
    assert.equal(result.shortfall, 0);
  });

  it('no batches at all is a total shortfall', () => {
    const result = allocateFefo([], 7);
    assert.deepEqual(result.draws, []);
    assert.equal(result.shortfall, 7);
  });

  it('rejects a negative quantity', () => {
    assert.throws(() => allocateFefo([batch('a', 10, 1)], -1), RangeError);
  });

  it('rejects a non-integer quantity', () => {
    assert.throws(() => allocateFefo([batch('a', 10, 1)], 1.5), RangeError);
  });

  it('a defensively negative remainingQuantity is treated as unavailable, not as a negative draw', () => {
    const result = allocateFefo([batch('bad', -3, 1), batch('good', 5, 2)], 5);
    assert.deepEqual(result.draws, [{ batchId: 'good', quantity: 5, unitCostCentavos: 1000 }]);
    assert.equal(result.shortfall, 0);
  });

  it('preserves each batch\'s own unit cost in its draw', () => {
    const result = allocateFefo(
      [batch('cheap', 5, 1, 800), batch('pricier', 5, 2, 1200)],
      8,
    );
    assert.deepEqual(result.draws, [
      { batchId: 'cheap', quantity: 5, unitCostCentavos: 800 },
      { batchId: 'pricier', quantity: 3, unitCostCentavos: 1200 },
    ]);
  });
});
