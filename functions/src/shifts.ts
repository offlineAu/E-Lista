/**
 * End-of-shift cash reconciliation.
 *
 * A snapshot record, not a shift lifecycle: no clock-in/clock-out state, no concept of
 * "the current shift" — just an audit-log row the owner can review afterward. What the
 * drawer should hold, what was actually counted, and the difference between them.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { CashCountError, resolveCashCount } from './domain/cash_count';
import {
  asObject,
  db,
  optionalString,
  paths,
  requireInt,
  requireOwnerOrCashier,
} from './lib/context';

/**
 * Records one cash-drawer count. Owner or cashier — this is the same "processing sales at
 * the register" boundary {@link requireOwnerOrCashier} already draws elsewhere.
 */
export const recordCashCount = onCall(async (request) => {
  const caller = requireOwnerOrCashier(request);
  const data = asObject(request.data);

  const expectedCentavos = requireInt(data, 'expectedCentavos', { min: 0 });
  const countedCentavos = requireInt(data, 'countedCentavos', { min: 0 });
  const note = optionalString(data, 'note', { maxLength: 300 });

  let outcome;
  try {
    outcome = resolveCashCount({ expectedCentavos, countedCentavos });
  } catch (error) {
    if (error instanceof CashCountError) {
      throw new HttpsError('invalid-argument', error.message);
    }
    throw error;
  }

  const ref = db.collection(paths.cashCounts).doc();
  await ref.set({
    cashierId: caller.uid,
    cashierName: caller.name ?? null,
    expectedCentavos: outcome.expectedCentavos,
    countedCentavos: outcome.countedCentavos,
    differenceCentavos: outcome.differenceCentavos,
    note: note ?? null,
    recordedAt: FieldValue.serverTimestamp(),
  });

  return { id: ref.id, ...outcome };
});
