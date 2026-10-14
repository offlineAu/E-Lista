/**
 * FEFO (first-expire-first-out) batch allocation.
 *
 * Deciding which batches a sale or a write-off draws from is pure arithmetic over whatever
 * batches it is handed — it never touches Firestore itself. `functions/src/lib/batches.ts`
 * reads the actual `productBatches` documents and maps them into the shapes this file
 * understands; `orders.ts` (`placeOrder`) and `inventory.ts` (`adjustInventory`) are the only
 * callers that commit the result.
 */

/** One batch's remaining availability, as seen by the allocator. */
export interface BatchAvailability {
  batchId: string;
  remainingQuantity: number;
  /** Epoch millis. A batch with no real expiry carries a sentinel far-future value, so it
   *  always sorts after everything that actually expires. */
  expiryDateMillis: number;
  unitCostCentavos: number;
}

/** How much of `quantity` was drawn from one specific batch, and at what cost. */
export interface BatchDraw {
  batchId: string;
  quantity: number;
  unitCostCentavos: number;
}

export interface FefoAllocation {
  /** One entry per batch actually drawn from, oldest-expiring first. */
  draws: BatchDraw[];
  /** Total units covered by `draws`. */
  fulfilled: number;
  /** `quantityNeeded - fulfilled`. Zero unless the batches on hand do not cover the whole
   *  request — which happens for stock that predates batch tracking, not as an error. */
  shortfall: number;
}

/**
 * Decides which batches cover `quantityNeeded`, oldest-expiring first.
 *
 * Never throws for insufficient stock: a non-zero `shortfall` is the caller's signal that
 * the batches on hand do not cover the request, which `placeOrder` and `adjustInventory`
 * both treat as untracked (pre-batch-tracking) stock rather than a data error. It does throw
 * for a malformed request, since a negative or fractional quantity is a caller bug, not a
 * business situation.
 */
export function allocateFefo(
  batches: BatchAvailability[],
  quantityNeeded: number,
): FefoAllocation {
  if (!Number.isSafeInteger(quantityNeeded) || quantityNeeded < 0) {
    throw new RangeError('quantityNeeded must be a non-negative whole number.');
  }

  const sorted = [...batches]
    .filter((batch) => batch.remainingQuantity > 0)
    .sort((a, b) =>
      a.expiryDateMillis !== b.expiryDateMillis
        ? a.expiryDateMillis - b.expiryDateMillis
        // Equal expiry: break the tie on batchId so two runs over the same input always
        // draw in the same order, rather than depending on however the batches arrived.
        : a.batchId.localeCompare(b.batchId),
    );

  const draws: BatchDraw[] = [];
  let remaining = quantityNeeded;

  for (const batch of sorted) {
    if (remaining <= 0) break;
    const take = Math.min(batch.remainingQuantity, remaining);
    draws.push({
      batchId: batch.batchId,
      quantity: take,
      unitCostCentavos: batch.unitCostCentavos,
    });
    remaining -= take;
  }

  return { draws, fulfilled: quantityNeeded - remaining, shortfall: remaining };
}
