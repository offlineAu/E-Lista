/**
 * Creating and editing products, and the price history that follows from it.
 *
 * The owner supplies a cost and a profit percentage; the server derives the two selling
 * prices. Doing it here rather than trusting a client-supplied price is what makes the
 * catalog's prices consistent with the store's actual pricing policy, and it is why a
 * change to the store-wide profit percentage can safely re-price every product at once.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  assertUsableProfit,
  DEFAULT_PROFIT_BASIS_POINTS,
  effectiveProfitBasisPoints,
  parsePricingMode,
  pricesFor,
  type PricingMode,
} from './domain/pricing';
import { writeNewBatch } from './lib/batches';
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
  type Caller,
  type DocumentWriter,
} from './lib/context';

/** Lower-cased prefixes of the name, brand and category, backing catalog search. */
export function buildSearchTokens(input: {
  name: string;
  brand?: string;
  categoryName?: string;
  barcode?: string;
}): string[] {
  const tokens = new Set<string>();

  for (const field of [input.name, input.brand, input.categoryName]) {
    if (!field) continue;
    for (const word of normaliseForSearch(field).split(' ')) {
      if (word.length < 2) continue;
      for (let length = 2; length <= word.length; length++) {
        tokens.add(word.slice(0, length));
      }
    }
  }

  if (input.barcode && input.barcode.length >= 4) {
    tokens.add(input.barcode);
    tokens.add(input.barcode.slice(-4));
  }

  return [...tokens].sort();
}

/** Lower-cases, strips accents, and reduces punctuation to spaces. */
export function normaliseForSearch(input: string): string {
  return input
    .toLowerCase()
    .normalize('NFD')
    // Strip combining marks left behind by NFD, so "Café" folds to "cafe".
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function readStoreDefaultProfit(): Promise<number> {
  const snapshot = await pricingSettingsDoc().get();
  const value = snapshot.data()?.defaultProfitBasisPoints;
  return typeof value === 'number' && Number.isSafeInteger(value)
    ? value
    : DEFAULT_PROFIT_BASIS_POINTS;
}

function assertBarcode(barcode: string | undefined): string | undefined {
  if (barcode === undefined) return undefined;
  if (!/^\d{8,14}$/.test(barcode)) {
    throw new HttpsError(
      'invalid-argument',
      'A barcode is 8 to 14 digits, numbers only.',
    );
  }
  return barcode;
}

/** Refuses to create a second product carrying the same barcode. */
async function assertBarcodeIsFree(barcode: string, ignoreProductId?: string) {
  const existing = await db
    .collection(paths.products)
    .where('barcode', '==', barcode)
    .limit(2)
    .get();

  const clash = existing.docs.find((doc) => doc.id !== ignoreProductId);
  if (clash) {
    const name = clash.data().name ?? 'another product';
    throw new HttpsError(
      'already-exists',
      `That barcode already belongs to ${name}. Restock it instead of adding it again.`,
    );
  }
}

interface PriceHistoryInput {
  productId: string;
  productName: string;
  reason: 'created' | 'productEdited' | 'restock' | 'storeDefaultChanged';
  caller: Caller;
  previous?: {
    costCentavos: number;
    cashCentavos: number;
    gcashCentavos: number;
    profitBasisPoints: number;
    pricingMode: PricingMode;
  };
  next: {
    costCentavos: number;
    cashCentavos: number;
    gcashCentavos: number;
    profitBasisPoints: number;
    pricingMode: PricingMode;
  };
}

/** Appends one row to the pricing audit trail. Never updates or deletes. */
export function writePriceHistory(
  batch: DocumentWriter,
  input: PriceHistoryInput,
) {
  const ref = db.collection(paths.productPriceHistory).doc();
  batch.set(ref, {
    productId: input.productId,
    productName: input.productName,
    reason: input.reason,
    oldCostPriceCentavos: input.previous?.costCentavos ?? null,
    oldCashPriceCentavos: input.previous?.cashCentavos ?? null,
    oldGcashPriceCentavos: input.previous?.gcashCentavos ?? null,
    oldProfitBasisPoints: input.previous?.profitBasisPoints ?? null,
    oldPricingMode: input.previous?.pricingMode ?? null,
    newCostPriceCentavos: input.next.costCentavos,
    newCashPriceCentavos: input.next.cashCentavos,
    newGcashPriceCentavos: input.next.gcashCentavos,
    newProfitBasisPoints: input.next.profitBasisPoints,
    newPricingMode: input.next.pricingMode,
    changedBy: input.caller.uid,
    changedByName: input.caller.name ?? null,
    changedAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Creates or updates a product.
 *
 * Prices are always derived, never accepted from the client. Initial stock on creation
 * also writes an opening ledger row, so a product's stock has an explanation from its very
 * first unit.
 */
export const saveProduct = onCall(async (request) => {
  const caller = requireOwner(request);
  const data = asObject(request.data);

  const productId = optionalString(data, 'productId', { maxLength: 128 });
  const name = requireString(data, 'name', { maxLength: 120 });
  const barcode = assertBarcode(optionalString(data, 'barcode', { maxLength: 20 }));
  const brand = optionalString(data, 'brand', { maxLength: 80 });
  const categoryId = optionalString(data, 'categoryId', { maxLength: 80 });
  const description = optionalString(data, 'description', { maxLength: 1000 });
  const imageUrl = optionalString(data, 'imageUrl', { maxLength: 500 });
  const unit = optionalString(data, 'unit', { maxLength: 16 }) ?? 'pc';
  const source = optionalString(data, 'source', { maxLength: 32 }) ?? 'manual';

  const costPriceCentavos = requireInt(data, 'costPriceCentavos', {
    min: 0,
    max: 100_000_000,
  });
  const pricingMode = parsePricingMode(data.pricingMode);
  const rawProfit = optionalInt(data, 'profitBasisPoints', { min: 0, max: 100_000 });
  const profitBasisPoints =
    pricingMode === 'custom' && rawProfit !== undefined
      ? assertUsableProfit(rawProfit)
      : undefined;

  const lowStockThreshold = optionalInt(data, 'lowStockThreshold', {
    min: 0,
    max: 100_000,
  }) ?? 0;
  const initialStock = optionalInt(data, 'initialStock', { min: 0, max: 1_000_000 });
  const expiryDateMillis = optionalInt(data, 'expiryDateMillis', { min: 0 });

  const isActive = data.isActive === undefined ? true : data.isActive === true;

  const storeDefault = await readStoreDefaultProfit();
  const effectiveProfit = effectiveProfitBasisPoints(
    pricingMode,
    profitBasisPoints,
    storeDefault,
  );
  const prices = pricesFor(costPriceCentavos, effectiveProfit);

  let categoryName: string | undefined;
  if (categoryId) {
    const categorySnapshot = await db.collection(paths.categories).doc(categoryId).get();
    const value = categorySnapshot.data()?.name;
    if (typeof value === 'string') categoryName = value;
  }

  const isCreate = productId === undefined;
  if (barcode) {
    await assertBarcodeIsFree(barcode, productId);
  }

  // `doc()` with no argument mints a new id; `doc(undefined)` would do the same silently,
  // so the update path passes a narrowed, definitely-present id.
  const productRef =
    productId === undefined
      ? db.collection(paths.products).doc()
      : db.collection(paths.products).doc(productId);

  return db.runTransaction(async (transaction) => {
    const existingSnapshot = isCreate ? null : await transaction.get(productRef);
    if (!isCreate && (existingSnapshot === null || !existingSnapshot.exists)) {
      throw new HttpsError('not-found', 'That product could not be found.');
    }

    const existingCostSnapshot = isCreate
      ? null
      : await transaction.get(productPricingDoc(productRef.id));

    const existing = existingSnapshot?.data() as Record<string, unknown> | undefined;
    const existingCost = existingCostSnapshot?.data() as
      | Record<string, unknown>
      | undefined;

    const stockQuantity = isCreate
      ? initialStock ?? 0
      : Number(existing?.stockQuantity ?? 0);

    transaction.set(
      productRef,
      {
        name,
        nameLower: name.toLowerCase(),
        barcode: barcode ?? null,
        brand: brand ?? null,
        categoryId: categoryId ?? null,
        description: description ?? null,
        imageUrl: imageUrl ?? null,
        unit,
        source,
        isActive,
        cashPriceCentavos: prices.cashPriceCentavos,
        gcashBasePriceCentavos: prices.gcashBasePriceCentavos,
        stockQuantity,
        lowStockThreshold,
        isLowStock: stockQuantity <= lowStockThreshold,
        searchTokens: buildSearchTokens({ name, brand, categoryName, barcode }),
        ...(isCreate ? { createdAt: FieldValue.serverTimestamp() } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    transaction.set(productPricingDoc(productRef.id), {
      costPriceCentavos,
      pricingMode,
      profitPercentageBasisPoints: profitBasisPoints ?? null,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: caller.uid,
    });

    const previousCost = Number(existingCost?.costPriceCentavos ?? 0);
    const previousCash = Number(existing?.cashPriceCentavos ?? 0);
    const previousGcash = Number(existing?.gcashBasePriceCentavos ?? 0);
    const changed =
      isCreate ||
      previousCost !== costPriceCentavos ||
      previousCash !== prices.cashPriceCentavos ||
      previousGcash !== prices.gcashBasePriceCentavos;

    if (changed) {
      writePriceHistory(transaction, {
        productId: productRef.id,
        productName: name,
        reason: isCreate ? 'created' : 'productEdited',
        caller,
        previous: isCreate
          ? undefined
          : {
              costCentavos: previousCost,
              cashCentavos: previousCash,
              gcashCentavos: previousGcash,
              profitBasisPoints: Number(
                existingCost?.profitPercentageBasisPoints ?? storeDefault,
              ),
              pricingMode: parsePricingMode(existingCost?.pricingMode),
            },
        next: {
          costCentavos: costPriceCentavos,
          cashCentavos: prices.cashPriceCentavos,
          gcashCentavos: prices.gcashBasePriceCentavos,
          profitBasisPoints: effectiveProfit,
          pricingMode,
        },
      });
    }

    if (isCreate && stockQuantity > 0) {
      // Minted before both writes so the ledger row and the opening batch can carry each
      // other's id, the same cross-reference adjustInventory's restock path uses.
      const ledgerRef = db.collection(paths.inventoryTransactions).doc();
      const referenceType = source === 'catalogImport' ? 'import' : 'manual';

      const batchRef = writeNewBatch(transaction, {
        productId: productRef.id,
        productName: name,
        quantity: stockQuantity,
        unitCostCentavos: costPriceCentavos,
        expiryDateMillis,
        sourceReferenceType: referenceType,
        sourceTransactionId: ledgerRef.id,
        performedBy: caller.uid,
        performedByName: caller.name,
      });

      transaction.set(ledgerRef, {
        productId: productRef.id,
        productName: name,
        type: 'restock',
        quantity: stockQuantity,
        previousStock: 0,
        newStock: stockQuantity,
        referenceType,
        referenceId: null,
        unitCostCentavos: costPriceCentavos,
        reason: 'Opening stock',
        batchId: batchRef.id,
        batchDraws: [],
        performedBy: caller.uid,
        performedByName: caller.name ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    return {
      productId: productRef.id,
      cashPriceCentavos: prices.cashPriceCentavos,
      gcashBasePriceCentavos: prices.gcashBasePriceCentavos,
      profitBasisPoints: effectiveProfit,
    };
  });
});

/**
 * Hides a product from the catalog, or brings it back.
 *
 * Deactivating rather than deleting: past orders reference the product, and the ledger has
 * to keep explaining where its stock went. A deleted product would leave both with a hole.
 */
export const setProductActive = onCall(async (request) => {
  requireOwner(request);
  const data = asObject(request.data);

  const productId = requireString(data, 'productId', { maxLength: 128 });
  const isActive = data.isActive === true;

  const ref = db.collection(paths.products).doc(productId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError('not-found', 'That product could not be found.');
  }

  await ref.update({
    isActive,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { productId, isActive };
});
