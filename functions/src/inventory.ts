/**
 * Stock movements.
 *
 * Every change to a product's stock goes through here and writes a ledger row in the same
 * Firestore transaction. That pairing is the whole design: a stock number with no
 * explanation is not an inventory, and a ledger that can disagree with the balance is
 * worse than none.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { allocateFefo, type BatchDraw } from './domain/fefo';
import {
  effectiveProfitBasisPoints,
  parsePricingMode,
  pricesFor,
  DEFAULT_PROFIT_BASIS_POINTS,
} from './domain/pricing';
import { batchDoc, batchesQueryForFefo, toBatchAvailability, writeNewBatch } from './lib/batches';
import {
  asObject,
  db,
  optionalInt,
  optionalString,
  paths,
  pricingSettingsDoc,
  productPricingDoc,
  requireInt,
  requireOwnerOrCashier,
  requireString,
} from './lib/context';
import { writePriceHistory } from './products';

/** Movement types an owner may record by hand. Sales come from the order flow only. */
const MANUAL_TYPES = ['restock', 'adjustment', 'damage', 'expired', 'returned'] as const;
type ManualType = (typeof MANUAL_TYPES)[number];

/** Which direction each type moves stock. `null` means either (adjustments). */
const DIRECTION: Record<ManualType, 1 | -1 | null> = {
  restock: 1,
  adjustment: null,
  damage: -1,
  expired: -1,
  returned: 1,
};

function parseType(value: unknown): ManualType {
  if (typeof value === 'string' && (MANUAL_TYPES as readonly string[]).includes(value)) {
    return value as ManualType;
  }
  throw new HttpsError('invalid-argument', 'Choose a valid stock movement.');
}

/**
 * Records a stock movement.
 *
 * `quantity` is always a positive count of units; the movement type decides the direction,
 * except for an adjustment, where `direction` says whether the count went up or down after
 * a physical recount.
 *
 * A restock may carry a new receipt cost. When it does, the product is re-priced and a
 * price-history row is appended — a delivery at a new price is the normal way a sari-sari
 * store's costs change, and it should not require a second trip to the edit screen.
 *
 * A cashier may record everything here except a restock or a cost change — those are the
 * two ways this function can move a price, which stays owner-only.
 *
 * A restock always opens a new batch, carrying whatever expiry date came with it. Damage,
 * expired and a downward adjustment always draw down a specific batch when the product has
 * any — an explicit `batchId` targets one directly, and leaving it out auto-selects via the
 * same FEFO rule a sale uses, so a write-off comes off the oldest stock by default. A
 * product with no batches yet (never restocked with a date) behaves exactly as before this
 * feature existed: no batch is touched, only the flat stock count.
 */
export const adjustInventory = onCall(async (request) => {
  const caller = requireOwnerOrCashier(request);
  const data = asObject(request.data);

  const productId = requireString(data, 'productId', { maxLength: 128 });
  const type = parseType(data.type);
  const quantity = requireInt(data, 'quantity', { min: 1, max: 1_000_000 });
  const reason = optionalString(data, 'reason', { maxLength: 300 });
  const unitCostCentavos = optionalInt(data, 'unitCostCentavos', {
    min: 0,
    max: 100_000_000,
  });
  const expiryDateMillis = optionalInt(data, 'expiryDateMillis', { min: 0 });
  const batchId = optionalString(data, 'batchId', { maxLength: 128 });

  const direction = DIRECTION[type] ?? (data.direction === 'decrease' ? -1 : 1);
  const signedQuantity = direction * quantity;
  const isDecrease = signedQuantity < 0;
  const batchIdAllowed =
    type === 'damage' ||
    type === 'expired' ||
    type === 'returned' ||
    (type === 'adjustment' && isDecrease);

  if (type === 'adjustment' && reason === undefined) {
    throw new HttpsError(
      'invalid-argument',
      'Say why the count is being adjusted, so the history makes sense later.',
    );
  }
  if (unitCostCentavos !== undefined && type !== 'restock') {
    throw new HttpsError(
      'invalid-argument',
      'A new cost can only be recorded with a restock.',
    );
  }
  if (caller.role === 'cashier' && (type === 'restock' || unitCostCentavos !== undefined)) {
    throw new HttpsError(
      'permission-denied',
      'Only the store owner can record a restock or change a cost.',
    );
  }
  if (expiryDateMillis !== undefined && type !== 'restock') {
    throw new HttpsError(
      'invalid-argument',
      'An expiry date can only be recorded with a restock.',
    );
  }
  if (batchId !== undefined && !batchIdAllowed) {
    throw new HttpsError(
      'invalid-argument',
      'A batch cannot be chosen for this kind of movement.',
    );
  }

  const storeDefaultSnapshot = await pricingSettingsDoc().get();
  const storeDefault =
    typeof storeDefaultSnapshot.data()?.defaultProfitBasisPoints === 'number'
      ? (storeDefaultSnapshot.data()!.defaultProfitBasisPoints as number)
      : DEFAULT_PROFIT_BASIS_POINTS;

  const productRef = db.collection(paths.products).doc(productId);
  // A write-off (damage/expired/adjustment-decrease) draws down a batch, either the one
  // named or, failing that, whichever this product has that isn't already exhausted.
  const drawsFromBatches = isDecrease && type !== 'restock';

  return db.runTransaction(async (transaction) => {
    const productSnapshot = await transaction.get(productRef);
    if (!productSnapshot.exists) {
      throw new HttpsError('not-found', 'That product could not be found.');
    }
    const costSnapshot = await transaction.get(productPricingDoc(productId));

    // All reads must happen before any write in a Firestore transaction, so the batch(es)
    // this movement will touch are read here, before the product/price/ledger writes below.
    let targetBatchSnapshot: FirebaseFirestore.DocumentSnapshot | undefined;
    let fefoBatchSnapshots: FirebaseFirestore.QuerySnapshot | undefined;
    if (drawsFromBatches) {
      if (batchId !== undefined) {
        targetBatchSnapshot = await transaction.get(batchDoc(batchId));
      } else {
        fefoBatchSnapshots = await transaction.get(batchesQueryForFefo(productId));
      }
    }

    const product = productSnapshot.data() as Record<string, unknown>;
    const productName = typeof product.name === 'string' ? product.name : 'Product';
    const previousStock = Number(product.stockQuantity ?? 0);
    const newStock = previousStock + signedQuantity;

    if (newStock < 0) {
      throw new HttpsError(
        'failed-precondition',
        `There are only ${previousStock} of ${productName} on hand, ` +
          `so ${quantity} cannot be removed.`,
      );
    }

    // Which batch(es) this write-off comes from, decided now that the reads are in hand.
    const batchDraws: BatchDraw[] = [];
    if (drawsFromBatches) {
      if (targetBatchSnapshot) {
        if (!targetBatchSnapshot.exists) {
          throw new HttpsError('not-found', 'That batch could not be found.');
        }
        const batchData = targetBatchSnapshot.data() as Record<string, unknown>;
        if (batchData.productId !== productId) {
          throw new HttpsError(
            'invalid-argument',
            'That batch belongs to a different product.',
          );
        }
        const remaining = Number(batchData.remainingQuantity ?? 0);
        if (remaining < quantity) {
          throw new HttpsError(
            'failed-precondition',
            `Only ${remaining} left in that batch, so ${quantity} cannot be removed from it.`,
          );
        }
        batchDraws.push({
          batchId: targetBatchSnapshot.id,
          quantity,
          unitCostCentavos: Number(batchData.unitCostCentavos ?? 0),
        });
      } else if (fefoBatchSnapshots && !fefoBatchSnapshots.empty) {
        const availability = fefoBatchSnapshots.docs.map(toBatchAvailability);
        // A shortfall here just means part of this write-off is untracked (pre-batch)
        // stock, same as placeOrder — the batches that do exist still get decremented.
        batchDraws.push(...allocateFefo(availability, quantity).draws);
      }
    }

    const threshold = Number(product.lowStockThreshold ?? 0);
    const productUpdates: Record<string, unknown> = {
      stockQuantity: newStock,
      isLowStock: newStock <= (Number.isSafeInteger(threshold) ? threshold : 0),
      updatedAt: FieldValue.serverTimestamp(),
    };

    // A delivery at a new cost re-prices the product.
    const cost = costSnapshot.data() as Record<string, unknown> | undefined;
    const previousCost = Number(cost?.costPriceCentavos ?? 0);

    if (unitCostCentavos !== undefined && unitCostCentavos !== previousCost) {
      const pricingMode = parsePricingMode(cost?.pricingMode);
      const productProfit = cost?.profitPercentageBasisPoints;
      const effectiveProfit = effectiveProfitBasisPoints(
        pricingMode,
        typeof productProfit === 'number' ? productProfit : null,
        storeDefault,
      );
      const prices = pricesFor(unitCostCentavos, effectiveProfit);

      productUpdates.cashPriceCentavos = prices.cashPriceCentavos;
      productUpdates.gcashBasePriceCentavos = prices.gcashBasePriceCentavos;

      transaction.set(
        productPricingDoc(productId),
        {
          costPriceCentavos: unitCostCentavos,
          updatedAt: FieldValue.serverTimestamp(),
          updatedBy: caller.uid,
        },
        { merge: true },
      );

      writePriceHistory(transaction, {
        productId,
        productName,
        reason: 'restock',
        caller,
        previous: {
          costCentavos: previousCost,
          cashCentavos: Number(product.cashPriceCentavos ?? 0),
          gcashCentavos: Number(product.gcashBasePriceCentavos ?? 0),
          profitBasisPoints: effectiveProfit,
          pricingMode,
        },
        next: {
          costCentavos: unitCostCentavos,
          cashCentavos: prices.cashPriceCentavos,
          gcashCentavos: prices.gcashBasePriceCentavos,
          profitBasisPoints: effectiveProfit,
          pricingMode,
        },
      });
    }

    transaction.update(productRef, productUpdates);

    // Minted before the ledger write so a new batch (or the ledger row itself) can carry
    // the other's id for cross-reference.
    const ledgerRef = db.collection(paths.inventoryTransactions).doc();

    let createdBatchId: string | null = null;
    if (type === 'restock') {
      const newBatchRef = writeNewBatch(transaction, {
        productId,
        productName,
        quantity,
        unitCostCentavos: unitCostCentavos ?? previousCost,
        expiryDateMillis,
        sourceReferenceType: 'manual',
        sourceTransactionId: ledgerRef.id,
        performedBy: caller.uid,
        performedByName: caller.name,
      });
      createdBatchId = newBatchRef.id;
    } else if (type === 'returned' && batchId !== undefined) {
      transaction.update(batchDoc(batchId), {
        remainingQuantity: FieldValue.increment(quantity),
      });
    } else {
      for (const draw of batchDraws) {
        transaction.update(batchDoc(draw.batchId), {
          remainingQuantity: FieldValue.increment(-draw.quantity),
        });
      }
    }

    transaction.set(ledgerRef, {
      productId,
      productName,
      type,
      quantity: signedQuantity,
      previousStock,
      newStock,
      referenceType: 'manual',
      referenceId: null,
      unitCostCentavos: unitCostCentavos ?? null,
      reason: reason ?? null,
      batchId: createdBatchId ?? (type === 'returned' ? batchId ?? null : null),
      batchDraws: batchDraws.map((draw) => ({
        batchId: draw.batchId,
        quantity: draw.quantity,
      })),
      performedBy: caller.uid,
      performedByName: caller.name ?? null,
      createdAt: FieldValue.serverTimestamp(),
    });

    return { productId, previousStock, newStock };
  });
});
