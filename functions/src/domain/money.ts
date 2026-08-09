/**
 * Integer-centavo money arithmetic.
 *
 * Every monetary value in E-Lista — on the client, in Firestore and here — is an integer
 * number of centavos. Binary floating point is never used for money: `0.1 + 0.2` is not
 * `0.3`, and a sari-sari store that is one centavo out on every GCash order notices.
 *
 * This module is the server-side mirror of `lib/core/money/money.dart`. The two
 * implementations must agree exactly; `test/pricing.test.ts` and
 * `test/pricing_test.dart` share the same table of cases.
 */

/** Percentages are integer basis points: 1% = 100 bp, so 20.5% = 2050 bp. */
export const BASIS_POINTS_PER_UNIT = 10000;

/** Centavos in one peso. */
export const CENTAVOS_PER_PESO = 100;

export class MoneyError extends Error {}

/** Throws unless `value` is a safe, finite integer. */
export function assertInteger(value: number, label: string): number {
  if (!Number.isSafeInteger(value)) {
    throw new MoneyError(`${label} must be a whole number of centavos, got ${value}`);
  }
  return value;
}

/** Divides two integers, rounding half away from zero. */
export function divideRoundHalfUp(numerator: number, denominator: number): number {
  if (denominator === 0) {
    throw new MoneyError('division by zero');
  }
  const sign = Math.sign(numerator) * Math.sign(denominator) || 1;
  const a = Math.abs(numerator);
  const b = Math.abs(denominator);
  return sign * Math.floor((2 * a + b) / (2 * b));
}

/** Divides two integers, rounding towards negative infinity. */
export function divideFloor(numerator: number, denominator: number): number {
  if (denominator === 0) {
    throw new MoneyError('division by zero');
  }
  return Math.floor(numerator / denominator);
}

/**
 * Cash selling price: cost plus a markup, then rounded **down to a whole peso**.
 *
 *   cashPrice = floor(costPrice × (1 + markup))
 *
 * Rounding is always down — never conventional rounding — because a sari-sari store
 * quotes whole pesos in cash and rounding up would surprise the customer.
 * ₱20.99, ₱20.50 and ₱20.01 all become ₱20.
 */
export function cashPriceCentavos(costCentavos: number, markupBasisPoints: number): number {
  assertInteger(costCentavos, 'costPrice');
  assertInteger(markupBasisPoints, 'markup');
  if (costCentavos < 0) {
    throw new MoneyError('costPrice cannot be negative');
  }
  if (markupBasisPoints < 0) {
    throw new MoneyError('markup cannot be negative');
  }
  const markedUp = costCentavos * (BASIS_POINTS_PER_UNIT + markupBasisPoints);
  const wholePesos = divideFloor(markedUp, BASIS_POINTS_PER_UNIT * CENTAVOS_PER_PESO);
  return wholePesos * CENTAVOS_PER_PESO;
}

/**
 * GCash base price: a **true profit margin**, not a markup.
 *
 *   gcashBasePrice = costPrice / (1 − margin)
 *
 * ₱15.00 at a 20% margin is ₱18.75, of which exactly 20% (₱3.75) is profit. Centavos are
 * preserved — this price is not rounded to whole pesos.
 */
export function gcashBasePriceCentavos(costCentavos: number, marginBasisPoints: number): number {
  assertInteger(costCentavos, 'costPrice');
  assertInteger(marginBasisPoints, 'margin');
  if (costCentavos < 0) {
    throw new MoneyError('costPrice cannot be negative');
  }
  if (marginBasisPoints < 0) {
    throw new MoneyError('margin cannot be negative');
  }
  if (marginBasisPoints >= BASIS_POINTS_PER_UNIT) {
    throw new MoneyError('margin must be below 100% — a 100% margin has no finite price');
  }
  return divideRoundHalfUp(
    costCentavos * BASIS_POINTS_PER_UNIT,
    BASIS_POINTS_PER_UNIT - marginBasisPoints,
  );
}

/** Formats centavos for logs and receipts: 1875 → "₱18.75", 1800 → "₱18". */
export function formatCentavos(centavos: number): string {
  const negative = centavos < 0;
  const abs = Math.abs(centavos);
  const pesos = Math.floor(abs / CENTAVOS_PER_PESO);
  const remainder = abs % CENTAVOS_PER_PESO;
  const body =
    remainder === 0
      ? `${pesos}`
      : `${pesos}.${remainder.toString().padStart(2, '0')}`;
  return `${negative ? '-' : ''}₱${body}`;
}
