/**
 * End-of-shift cash reconciliation arithmetic.
 *
 * Pure and tiny on purpose, same reasoning as `domain/tender.ts`: the one number a cashier
 * actually cares about — over or short, and by how much — belongs in one tested place.
 */

/** An expected or counted amount that cannot be accepted — missing or malformed. */
export class CashCountError extends Error {}

export interface CashCountInput {
  /** What the drawer should hold, from today's recorded cash sales. */
  expectedCentavos: number;
  /** What was actually counted. */
  countedCentavos: number;
}

export interface CashCountOutcome extends CashCountInput {
  /** `counted - expected`. Positive means over, negative means short. */
  differenceCentavos: number;
}

export function resolveCashCount(input: CashCountInput): CashCountOutcome {
  if (!Number.isSafeInteger(input.expectedCentavos) || input.expectedCentavos < 0) {
    throw new CashCountError('The expected amount must be a whole, non-negative number.');
  }
  if (!Number.isSafeInteger(input.countedCentavos) || input.countedCentavos < 0) {
    throw new CashCountError('The counted amount must be a whole, non-negative number.');
  }

  return {
    expectedCentavos: input.expectedCentavos,
    countedCentavos: input.countedCentavos,
    differenceCentavos: input.countedCentavos - input.expectedCentavos,
  };
}
