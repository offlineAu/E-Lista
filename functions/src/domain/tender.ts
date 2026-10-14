/**
 * Cash tendered and change due for a walk-in sale.
 *
 * Pure arithmetic, deliberately kept out of `orders.ts`: money math that decides how much
 * change a cashier hands back belongs in one tested place, not inlined in a transaction.
 */

export type PaymentMethod = 'cash' | 'gcash';

/** A tender amount that cannot be accepted — missing, malformed, or short of the total. */
export class TenderError extends Error {}

export interface TenderInput {
  paymentMethod: PaymentMethod;
  totalCentavos: number;
  /** Present only for cash. Ignored for GCash — a digital payment is exact by construction. */
  amountTenderedCentavos?: number;
}

export interface TenderOutcome {
  /** `null` for GCash: recording a tendered/change pair on an exact digital payment would
   *  imply a cash-handling event that never happened. */
  amountTenderedCentavos: number | null;
  changeCentavos: number | null;
}

/**
 * Resolves what a sale's receipt should show for tendered cash and change.
 *
 * Throws {@link TenderError} for cash with no tendered amount, a non-integer or negative
 * amount, or an amount short of the total — never for GCash, which ignores whatever was
 * passed.
 */
export function resolveTender(input: TenderInput): TenderOutcome {
  if (input.paymentMethod === 'gcash') {
    return { amountTenderedCentavos: null, changeCentavos: null };
  }

  if (input.amountTenderedCentavos === undefined) {
    throw new TenderError('Enter the amount tendered.');
  }

  const { amountTenderedCentavos, changeCentavos } = resolveCashTender(
    input.totalCentavos,
    input.amountTenderedCentavos,
  );
  return { amountTenderedCentavos, changeCentavos };
}

/** The cash-only arithmetic, exported separately so it can be tested in isolation. */
export function resolveCashTender(
  totalCentavos: number,
  amountTenderedCentavos: number,
): { amountTenderedCentavos: number; changeCentavos: number } {
  if (!Number.isSafeInteger(amountTenderedCentavos) || amountTenderedCentavos < 0) {
    throw new TenderError('Amount tendered must be a whole, non-negative number.');
  }
  if (amountTenderedCentavos < totalCentavos) {
    throw new TenderError('Amount tendered is less than the total.');
  }
  return {
    amountTenderedCentavos,
    changeCentavos: amountTenderedCentavos - totalCentavos,
  };
}
