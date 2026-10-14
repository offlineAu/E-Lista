/**
 * Pricing rules, server side.
 *
 * This is the authority. The Flutter client computes the same numbers so it can show a
 * price before the round trip, but what a customer is charged is always what this file
 * produces from what is in Firestore.
 *
 * Mirrors `lib/features/pricing/domain/pricing_engine.dart`. Cash and GCash share the same
 * markup formula; only the transaction-level GCash convenience fee differs.
 */

import { HttpsError } from 'firebase-functions/v2/https';

import { cashPriceCentavos, gcashBasePriceCentavos } from './money';

export type PricingMode = 'standard' | 'custom';

export interface ProductPrices {
  cashPriceCentavos: number;
  gcashBasePriceCentavos: number;
}

/** Highest profit percentage the settings accept, exclusive: 90%. */
export const MAX_PROFIT_BASIS_POINTS = 9000;

/** What a brand-new store starts with: 20%. */
export const DEFAULT_PROFIT_BASIS_POINTS = 2000;

export function parsePricingMode(value: unknown): PricingMode {
  return value === 'custom' ? 'custom' : 'standard';
}

/**
 * The percentage a product actually prices itself with.
 *
 * A `standard` product follows the store-wide figure, so raising the store default
 * re-prices it. A `custom` product keeps its own and is unaffected — which is the whole
 * point of the distinction.
 */
export function effectiveProfitBasisPoints(
  mode: PricingMode,
  productBasisPoints: number | null | undefined,
  storeDefaultBasisPoints: number,
): number {
  if (mode === 'custom' && typeof productBasisPoints === 'number') {
    return productBasisPoints;
  }
  return storeDefaultBasisPoints;
}

/** Both selling prices for one cost and one profit percentage. */
export function pricesFor(
  costCentavos: number,
  profitBasisPoints: number,
): ProductPrices {
  return {
    cashPriceCentavos: cashPriceCentavos(costCentavos, profitBasisPoints),
    gcashBasePriceCentavos: gcashBasePriceCentavos(costCentavos, profitBasisPoints),
  };
}

/** Validates a profit percentage, with a message aimed at the owner. */
export function assertUsableProfit(basisPoints: number): number {
  if (!Number.isSafeInteger(basisPoints)) {
    throw new HttpsError('invalid-argument', 'Profit must be a whole number of basis points.');
  }
  if (basisPoints < 0) {
    throw new HttpsError('invalid-argument', 'Profit cannot be negative.');
  }
  if (basisPoints >= MAX_PROFIT_BASIS_POINTS) {
    throw new HttpsError(
      'invalid-argument',
      'Profit must be below 90%.',
    );
  }
  return basisPoints;
}
