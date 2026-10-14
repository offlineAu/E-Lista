/**
 * Store settings: the default profit percentage and the GCash fee tiers.
 *
 * Changing the default profit is not just a stored number — it re-prices every product
 * that follows the store default, and each of those re-pricings appends a row to the price
 * history. Doing that here means the catalog, the cost records and the audit trail move
 * together instead of drifting apart.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  DEFAULT_GCASH_FEE_TIERS,
  GcashFeeConfigError,
  normaliseGcashFeeTiers,
  type GcashFeeTier,
} from './domain/gcash_fees';
import {
  assertUsableProfit,
  DEFAULT_PROFIT_BASIS_POINTS,
  parsePricingMode,
  pricesFor,
} from './domain/pricing';
import {
  asObject,
  db,
  gcashFeesDoc,
  gcashQrDoc,
  optionalString,
  paths,
  pricingSettingsDoc,
  productPricingDoc,
  requireInt,
  requireOwner,
} from './lib/context';
import { writePriceHistory } from './products';

/** Firestore's cap on operations in one batched write. */
const BATCH_LIMIT = 400;

/**
 * Sets the store-wide default profit percentage and re-prices everything that follows it.
 *
 * Products in `custom` mode keep their own percentage and are deliberately left alone:
 * that separation is the reason the mode exists.
 */
export const savePricingSettings = onCall(async (request) => {
  const caller = requireOwner(request);
  const data = asObject(request.data);

  const defaultProfitBasisPoints = assertUsableProfit(
    requireInt(data, 'defaultProfitBasisPoints', { min: 0, max: 100_000 }),
  );

  const previousSnapshot = await pricingSettingsDoc().get();
  const previousDefault =
    typeof previousSnapshot.data()?.defaultProfitBasisPoints === 'number'
      ? (previousSnapshot.data()!.defaultProfitBasisPoints as number)
      : DEFAULT_PROFIT_BASIS_POINTS;

  await pricingSettingsDoc().set(
    {
      defaultProfitBasisPoints,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: caller.uid,
    },
    { merge: true },
  );

  if (defaultProfitBasisPoints === previousDefault) {
    return { defaultProfitBasisPoints, repricedCount: 0 };
  }

  // Re-price every product on the store default. Read the whole catalog once and write in
  // batches: a sari-sari store has hundreds of products, not millions, and doing this in
  // one pass keeps the catalog internally consistent.
  const products = await db.collection(paths.products).get();
  let batch = db.batch();
  let operations = 0;
  let repricedCount = 0;

  for (const productDoc of products.docs) {
    const costSnapshot = await productPricingDoc(productDoc.id).get();
    const cost = costSnapshot.data();
    if (!cost) continue;

    const pricingMode = parsePricingMode(cost.pricingMode);
    if (pricingMode === 'custom') continue;

    const costCentavos = Number(cost.costPriceCentavos ?? 0);
    if (!Number.isSafeInteger(costCentavos) || costCentavos < 0) continue;

    const product = productDoc.data();
    const previousCash = Number(product.cashPriceCentavos ?? 0);
    const previousGcash = Number(product.gcashBasePriceCentavos ?? 0);
    const prices = pricesFor(costCentavos, defaultProfitBasisPoints);

    if (
      prices.cashPriceCentavos === previousCash &&
      prices.gcashBasePriceCentavos === previousGcash
    ) {
      continue;
    }

    batch.update(productDoc.ref, {
      cashPriceCentavos: prices.cashPriceCentavos,
      gcashBasePriceCentavos: prices.gcashBasePriceCentavos,
      updatedAt: FieldValue.serverTimestamp(),
    });
    operations++;
    repricedCount++;

    writePriceHistory(batch, {
      productId: productDoc.id,
      productName: typeof product.name === 'string' ? product.name : 'Product',
      reason: 'storeDefaultChanged',
      caller,
      previous: {
        costCentavos,
        cashCentavos: previousCash,
        gcashCentavos: previousGcash,
        profitBasisPoints: previousDefault,
        pricingMode,
      },
      next: {
        costCentavos,
        cashCentavos: prices.cashPriceCentavos,
        gcashCentavos: prices.gcashBasePriceCentavos,
        profitBasisPoints: defaultProfitBasisPoints,
        pricingMode,
      },
    });
    operations++;

    if (operations >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      operations = 0;
    }
  }

  if (operations > 0) await batch.commit();

  return { defaultProfitBasisPoints, repricedCount };
});

/**
 * Replaces the GCash convenience fee table.
 *
 * Validated before it is stored, because an overlapping or gappy table would make the fee
 * for some order totals ambiguous — and the moment to discover that is while the owner is
 * editing, not while a customer is checking out.
 */
export const saveGcashFeeTiers = onCall(async (request) => {
  const caller = requireOwner(request);
  const data = asObject(request.data);

  const raw = data.tiers;
  if (!Array.isArray(raw)) {
    throw new HttpsError('invalid-argument', 'Send the list of fee tiers.');
  }

  const parsed: GcashFeeTier[] = raw.map((entry, index) => {
    if (typeof entry !== 'object' || entry === null) {
      throw new HttpsError('invalid-argument', `Tier ${index + 1} is malformed.`);
    }
    const tier = entry as Record<string, unknown>;
    const min = tier.minCentavos;
    const max = tier.maxCentavos;
    const fee = tier.feeCentavos;

    if (typeof min !== 'number' || typeof fee !== 'number') {
      throw new HttpsError(
        'invalid-argument',
        `Tier ${index + 1} needs a minimum and a fee.`,
      );
    }
    if (max !== null && max !== undefined && typeof max !== 'number') {
      throw new HttpsError('invalid-argument', `Tier ${index + 1} has a bad maximum.`);
    }

    return {
      minCentavos: min,
      maxCentavos: max === undefined ? null : (max as number | null),
      feeCentavos: fee,
    };
  });

  let tiers: GcashFeeTier[];
  try {
    tiers = normaliseGcashFeeTiers(parsed);
  } catch (error) {
    if (error instanceof GcashFeeConfigError) {
      // The message is already written for the owner; pass it through unchanged.
      throw new HttpsError('invalid-argument', error.message);
    }
    throw error;
  }

  await gcashFeesDoc().set({
    tiers,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: caller.uid,
  });

  return { tierCount: tiers.length };
});

/**
 * Sets or clears the store's GCash "Scan to Pay" QR code.
 *
 * A static image, not a generated one: the owner uploads a picture of the QR their own
 * GCash app already produces (Profile → My QR Code), already stored in Firebase Storage by
 * the time this is called. This just records where it ended up — or, called with no
 * `imageUrl`, clears it so checkout stops showing a stale or removed code.
 */
export const saveGcashQr = onCall(async (request) => {
  const caller = requireOwner(request);
  const data = asObject(request.data);

  const imageUrl = optionalString(data, 'imageUrl', { maxLength: 2000 });

  await gcashQrDoc().set({
    imageUrl: imageUrl ?? null,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: caller.uid,
  });

  return { imageUrl: imageUrl ?? null };
});

/**
 * Writes the documents a brand-new store needs: default categories, default profit
 * percentage and the starting fee table.
 *
 * Idempotent — existing documents are left alone — so it is safe to run again after an
 * owner has already customised things.
 */
export const seedStore = onCall(async (request) => {
  requireOwner(request);

  const defaultCategories = [
    { id: 'snacks', name: 'Snacks', iconName: 'cookie', sortOrder: 10 },
    { id: 'beverages', name: 'Beverages', iconName: 'local_drink', sortOrder: 20 },
    {
      id: 'instant-noodles',
      name: 'Instant Noodles',
      iconName: 'ramen_dining',
      sortOrder: 30,
    },
    { id: 'canned-goods', name: 'Canned Goods', iconName: 'inventory_2', sortOrder: 40 },
    { id: 'rice-grains', name: 'Rice & Grains', iconName: 'rice_bowl', sortOrder: 50 },
    { id: 'condiments', name: 'Condiments', iconName: 'soup_kitchen', sortOrder: 60 },
    {
      id: 'household',
      name: 'Household',
      iconName: 'cleaning_services',
      sortOrder: 70,
    },
    { id: 'personal-care', name: 'Personal Care', iconName: 'soap', sortOrder: 80 },
    { id: 'school-office', name: 'School & Office', iconName: 'edit', sortOrder: 90 },
    { id: 'others', name: 'Others', iconName: 'category', sortOrder: 999 },
  ];

  const batch = db.batch();
  let created = 0;

  for (const category of defaultCategories) {
    const ref = db.collection(paths.categories).doc(category.id);
    const existing = await ref.get();
    if (existing.exists) continue;

    batch.set(ref, {
      name: category.name,
      nameLower: category.name.toLowerCase(),
      iconName: category.iconName,
      sortOrder: category.sortOrder,
      isActive: true,
      productCount: null,
    });
    created++;
  }

  const pricingExists = (await pricingSettingsDoc().get()).exists;
  if (!pricingExists) {
    batch.set(pricingSettingsDoc(), {
      defaultProfitBasisPoints: DEFAULT_PROFIT_BASIS_POINTS,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: null,
    });
  }

  const feesExist = (await gcashFeesDoc().get()).exists;
  if (!feesExist) {
    batch.set(gcashFeesDoc(), {
      tiers: normaliseGcashFeeTiers(DEFAULT_GCASH_FEE_TIERS),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: null,
    });
  }

  await batch.commit();

  return {
    categoriesCreated: created,
    pricingSeeded: !pricingExists,
    feesSeeded: !feesExist,
  };
});
