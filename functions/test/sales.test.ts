import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { computeSaleProfit } from '../src/domain/sales';

describe('computeSaleProfit', () => {
  it('a normal cash sale: gross profit is sales minus cost, net profit equals gross (no fee)', () => {
    assert.deepEqual(
      computeSaleProfit({
        grossSalesCentavos: 10000,
        productCostCentavos: 6000,
        convenienceFeeCentavos: 0,
      }),
      { grossProfitCentavos: 4000, netProfitCentavos: 4000 },
    );
  });

  it('a gcash sale adds the convenience fee on top of gross profit for net profit', () => {
    assert.deepEqual(
      computeSaleProfit({
        grossSalesCentavos: 10000,
        productCostCentavos: 6000,
        convenienceFeeCentavos: 250,
      }),
      { grossProfitCentavos: 4000, netProfitCentavos: 4250 },
    );
  });

  it('a loss-making line (cost exceeds sales) reports negative profit rather than clamping', () => {
    assert.deepEqual(
      computeSaleProfit({
        grossSalesCentavos: 5000,
        productCostCentavos: 8000,
        convenienceFeeCentavos: 0,
      }),
      { grossProfitCentavos: -3000, netProfitCentavos: -3000 },
    );
  });
});
