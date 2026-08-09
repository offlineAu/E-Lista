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

import {
  effectiveProfitBasisPoints,
  parsePricingMode,
  pricesFor,
  DEFAULT_PROFIT_BASIS_POINTS,
} from './domain/pricing';
import {
  asObject,
  db,
  optionalInt,
  optionalString,
  paths,
  pricingSettingsDoc,
  productPricingDoc,
  requireInt,
  requireOwner,
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
 */
export const adjustInventory = onCall(async (request) => {
  const caller = requireOwner(request);
  const data = asObject(request.data);

  const productId = requireString(data, 'productId', { maxLength: 128 });
  const type = parseType(data.type);
  const quantity = requireInt(data, 'quantity', { min: 1, max: 1_000_000 });
  const reason = optionalString(data, 'reason', { maxLength: 300 });
  const unitCostCentavos = optionalInt(data, 'unitCostCentavos', {
    min: 0,
    max: 100_000_000,
  });

  const direction = DIRECTION[type] ?? (data.direction === 'decrease' ? -1 : 1);
  const signedQuantity = direction * quantity;

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

  const storeDefaultSnapshot = await pricingSettingsDoc().get();
  const storeDefault =
    typeof storeDefaultSnapshot.data()?.defaultProfitBasisPoints === 'number'
      ? (storeDefaultSnapshot.data()!.defaultProfitBasisPoints as number)
      : DEFAULT_PROFIT_BASIS_POINTS;

  const productRef = db.collection(paths.products).doc(productId);

  return db.runTransaction(async (transaction) => {
    const productSnapshot = await transaction.get(productRef);
    if (!productSnapshot.exists) {
      throw new HttpsError('not-found', 'That product could not be found.');
    }
    const costSnapshot = await transaction.get(productPricingDoc(productId));

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

    transaction.set(db.collection(paths.inventoryTransactions).doc(), {
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
      performedBy: caller.uid,
      performedByName: caller.name ?? null,
      createdAt: FieldValue.serverTimestamp(),
    });

    return { productId, previousStock, newStock };
  });
});
