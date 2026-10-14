/**
 * Firestore-facing helpers for `productBatches` — the FEFO stock-lot ledger.
 *
 * Kept separate from `products.ts` and `inventory.ts` (rather than inside either) so both
 * of them, and `orders.ts`, can import from here without creating a cycle: `inventory.ts`
 * already imports `writePriceHistory` from `products.ts`, so `products.ts` cannot import
 * batch helpers back from `inventory.ts`.
 *
 * The actual FEFO decision (which batches to draw from) is pure logic in
 * `../domain/fefo.ts`; everything here is just reading and writing the documents that logic
 * operates on.
 */

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import type { BatchAvailability } from '../domain/fefo';
import { db, paths, type DocumentWriter } from './context';

export const batchDoc = (batchId: string) =>
  db.collection(paths.productBatches).doc(batchId);

/**
 * Every batch for a product, oldest-expiring first — the read FEFO allocation is built on.
 *
 * The limit is generous headroom, not a real cap: a fast-moving product restocked weekly
 * would need over half a year of undepleted batches to reach it, and a depleted batch
 * (usually also the one with the nearest expiry, since it was drawn from first) naturally
 * falls behind the ones still worth drawing from as it sinks toward the back of this
 * ascending-expiry order over time.
 */
export function batchesQueryForFefo(productId: string, limit = 30) {
  return db
    .collection(paths.productBatches)
    .where('productId', '==', productId)
    .orderBy('expiryDate', 'asc')
    .limit(limit);
}

/** Maps a `productBatches` document into the shape the pure FEFO allocator understands. */
export function toBatchAvailability(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
): BatchAvailability {
  const data = doc.data();
  const expiry = data.expiryDate;
  return {
    batchId: doc.id,
    remainingQuantity: Number(data.remainingQuantity ?? 0),
    expiryDateMillis: expiry instanceof Timestamp
      ? expiry.toMillis()
      : Number.MAX_SAFE_INTEGER,
    unitCostCentavos: Number(data.unitCostCentavos ?? 0),
  };
}

export interface NewBatchInput {
  productId: string;
  productName: string;
  quantity: number;
  unitCostCentavos: number;
  /** `undefined` means "no expiry" — stored as a far-future sentinel, mirroring the Dart
   *  model's `noExpirySentinel`, so ascending FEFO order always sorts it last. */
  expiryDateMillis?: number;
  sourceReferenceType: 'manual' | 'import';
  sourceTransactionId: string;
  performedBy: string;
  performedByName?: string | null;
}

/** A date far enough out that it never sorts before a batch with a real expiry. */
const NO_EXPIRY_SENTINEL_MILLIS = Date.UTC(9999, 11, 31);

/** Appends one new batch, with `remainingQuantity` starting equal to `quantity`. */
export function writeNewBatch(writer: DocumentWriter, input: NewBatchInput) {
  const ref = db.collection(paths.productBatches).doc();
  writer.set(ref, {
    productId: input.productId,
    productName: input.productName,
    initialQuantity: input.quantity,
    remainingQuantity: input.quantity,
    unitCostCentavos: input.unitCostCentavos,
    expiryDate: Timestamp.fromMillis(
      input.expiryDateMillis ?? NO_EXPIRY_SENTINEL_MILLIS,
    ),
    hasExpiry: input.expiryDateMillis !== undefined,
    sourceReferenceType: input.sourceReferenceType,
    sourceTransactionId: input.sourceTransactionId,
    receivedAt: FieldValue.serverTimestamp(),
    createdBy: input.performedBy,
    createdByName: input.performedByName ?? null,
  });
  return ref;
}
