/**
 * Firestore-facing helpers shared by `placeOrder` and `placeWalkInSale`.
 *
 * Both functions price a cart's lines, draw stock FEFO-first, and decrement it the same
 * way — the only real difference between a storefront order and a walk-in sale is what
 * happens to the order document afterward (pending vs. immediately completed, a real
 * contact vs. a synthetic one). This file is the shared middle, so that difference is the
 * only thing either function's own code has to express.
 */

import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import { allocateFefo, type BatchDraw } from '../domain/fefo';
import { computeSaleProfit } from '../domain/sales';
import { batchDoc, batchesQueryForFefo, toBatchAvailability } from './batches';
import { dayKeyFor, db, paths, productPricingDoc } from './context';

export interface RequestedLine {
  productId: string;
  quantity: number;
}

/** One batch's contribution to a line's cost, or `null` for untracked (pre-batch) stock. */
export interface CostLineBatch {
  batchId: string | null;
  quantity: number;
  unitCostCentavos: number;
}

interface StockWrite {
  ref: FirebaseFirestore.DocumentReference;
  previousStock: number;
  newStock: number;
  lowStockThreshold: number;
  productName: string;
  quantity: number;
  batchDraws: BatchDraw[];
}

export interface PricingReads {
  productRefs: FirebaseFirestore.DocumentReference[];
  productSnapshots: FirebaseFirestore.DocumentSnapshot[];
  costSnapshots: FirebaseFirestore.DocumentSnapshot[];
  batchQuerySnapshots: FirebaseFirestore.QuerySnapshot[];
}

/** The reads `priceAndAllocateLines` needs, gathered inside the caller's transaction. */
export async function readPricingSnapshots(
  transaction: FirebaseFirestore.Transaction,
  lines: RequestedLine[],
): Promise<PricingReads> {
  const productRefs = lines.map((line) => db.collection(paths.products).doc(line.productId));
  const costRefs = lines.map((line) => productPricingDoc(line.productId));

  const productSnapshots = await transaction.getAll(...productRefs);
  const costSnapshots = await transaction.getAll(...costRefs);
  // Bounded by the caller's own line-count cap, and each query is itself capped — see
  // batchesQueryForFefo's own limit — so this stays a small, known-size read set.
  const batchQuerySnapshots = await Promise.all(
    lines.map((line) => transaction.get(batchesQueryForFefo(line.productId))),
  );

  return { productRefs, productSnapshots, costSnapshots, batchQuerySnapshots };
}

export interface PricedLines {
  orderItems: Record<string, unknown>[];
  costLines: Record<string, unknown>[];
  stockWrites: StockWrite[];
  subtotalCentavos: number;
  productCostCentavos: number;
  itemCount: number;
}

/**
 * Validates every line, prices it from the product document (never from the client), and
 * draws FEFO batches for its cost — the same per-line work `placeOrder` always did, just
 * usable from more than one caller now.
 */
export function priceAndAllocateLines(
  params: PricingReads & { lines: RequestedLine[]; paymentMethod: 'cash' | 'gcash' },
): PricedLines {
  const { lines, paymentMethod, productRefs, productSnapshots, costSnapshots, batchQuerySnapshots } =
    params;

  const orderItems: Record<string, unknown>[] = [];
  const costLines: Record<string, unknown>[] = [];
  const stockWrites: StockWrite[] = [];

  let subtotalCentavos = 0;
  let productCostCentavos = 0;
  let itemCount = 0;

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    const snapshot = productSnapshots[index];

    if (!snapshot.exists) {
      throw new HttpsError(
        'failed-precondition',
        'One of these products is no longer in the store. Please remove it and try again.',
      );
    }

    const product = snapshot.data() as Record<string, unknown>;
    const name = typeof product.name === 'string' ? product.name : 'Product';

    if (product.isActive !== true) {
      throw new HttpsError(
        'failed-precondition',
        `${name} is no longer available. Please remove it and try again.`,
      );
    }

    const stock = Number(product.stockQuantity ?? 0);
    if (!Number.isSafeInteger(stock) || stock < line.quantity) {
      throw new HttpsError(
        'failed-precondition',
        stock <= 0 ? `${name} has just sold out.` : `Only ${stock} of ${name} left.`,
      );
    }

    // The price the store is charging right now, from the product document — never from
    // anything the client sent.
    const cashPrice = Number(product.cashPriceCentavos ?? 0);
    const gcashPrice = Number(product.gcashBasePriceCentavos ?? 0);
    const unitPrice = paymentMethod === 'cash' ? cashPrice : gcashPrice;

    if (!Number.isSafeInteger(unitPrice) || unitPrice < 0) {
      throw new HttpsError(
        'failed-precondition',
        `${name} is not priced correctly. Please ask the store to check it.`,
      );
    }

    const lineTotal = unitPrice * line.quantity;
    subtotalCentavos += lineTotal;
    itemCount += line.quantity;

    orderItems.push({
      productId: line.productId,
      productName: name,
      brand: product.brand ?? null,
      unit: product.unit ?? 'pc',
      imageUrl: product.imageUrl ?? null,
      quantity: line.quantity,
      cashPriceCentavos: cashPrice,
      gcashPriceCentavos: gcashPrice,
      selectedUnitPriceCentavos: unitPrice,
      lineTotalCentavos: lineTotal,
    });

    // The cost snapshot goes to an owner-only subdocument, never onto the order itself.
    const costData = costSnapshots[index].data() as Record<string, unknown> | undefined;
    const unitCost = Number(costData?.costPriceCentavos ?? 0);
    const safeUnitCost = Number.isSafeInteger(unitCost) && unitCost >= 0 ? unitCost : 0;

    // FEFO: draw from whichever batches this product has, oldest-expiring first. A product
    // that predates batch tracking has none, so `shortfall` covers the whole line at the
    // current cost — no backfill migration required for this to work.
    const availableBatches = batchQuerySnapshots[index].docs.map(toBatchAvailability);
    const allocation = allocateFefo(availableBatches, line.quantity);
    const lineBatches: CostLineBatch[] = allocation.draws.map((draw) => ({
      batchId: draw.batchId,
      quantity: draw.quantity,
      unitCostCentavos: draw.unitCostCentavos,
    }));
    if (allocation.shortfall > 0) {
      lineBatches.push({
        batchId: null,
        quantity: allocation.shortfall,
        unitCostCentavos: safeUnitCost,
      });
    }

    // The exact sum of what was actually drawn, not an average re-multiplied — batches
    // priced differently must not drift from a floor/round of their own total.
    const lineCostCentavos = lineBatches.reduce(
      (sum, draw) => sum + draw.quantity * draw.unitCostCentavos,
      0,
    );
    productCostCentavos += lineCostCentavos;
    costLines.push({
      productId: line.productId,
      // Display-only average, kept for anything already reading this field; the exact
      // total above is the ground truth.
      costPriceCentavos: Math.floor(lineCostCentavos / line.quantity),
      batches: lineBatches,
    });

    const threshold = Number(product.lowStockThreshold ?? 0);
    stockWrites.push({
      ref: productRefs[index],
      previousStock: stock,
      newStock: stock - line.quantity,
      lowStockThreshold: Number.isSafeInteger(threshold) ? threshold : 0,
      productName: name,
      quantity: line.quantity,
      batchDraws: allocation.draws,
    });
  }

  return { orderItems, costLines, stockWrites, subtotalCentavos, productCostCentavos, itemCount };
}

/**
 * Decrements stock for a sale: the product's flat count, an `inventoryTransactions` ledger
 * row per line, and each drawn batch's `remainingQuantity` — reserved at the moment of sale,
 * not at completion, which is the only way two sales cannot both claim the last unit.
 */
export function writeStockForSale(
  transaction: FirebaseFirestore.Transaction,
  params: {
    stockWrites: StockWrite[];
    orderId: string;
    performedBy: string;
    performedByName: string;
  },
): void {
  const { stockWrites, orderId, performedBy, performedByName } = params;

  for (const write of stockWrites) {
    transaction.update(write.ref, {
      stockQuantity: write.newStock,
      isLowStock: write.newStock <= write.lowStockThreshold,
      // Lifetime count, not net of any later cancellation — a "popular" signal for the
      // storefront, not an inventory figure.
      unitsSoldTotal: FieldValue.increment(write.quantity),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const ledgerRef = db.collection(paths.inventoryTransactions).doc();
    transaction.set(ledgerRef, {
      productId: write.ref.id,
      productName: write.productName,
      type: 'sale',
      quantity: -write.quantity,
      previousStock: write.previousStock,
      newStock: write.newStock,
      referenceType: 'order',
      referenceId: orderId,
      performedBy,
      performedByName,
      createdAt: FieldValue.serverTimestamp(),
    });

    for (const draw of write.batchDraws) {
      transaction.update(batchDoc(draw.batchId), {
        remainingQuantity: FieldValue.increment(-draw.quantity),
      });
    }
  }
}

/** Builds the `sales/{orderId}` record for a just-completed order or walk-in sale. */
export function buildSaleRecord(params: {
  orderId: string;
  paymentMethod: 'cash' | 'gcash';
  subtotalCentavos: number;
  convenienceFeeCentavos: number;
  productCostCentavos: number;
  itemCount: number;
  customerId: string | null;
  completedAt: Date;
  /** The cashier who rang this up, for a walk-in sale — `null` for a storefront order,
   *  which has no cashier and whose `customerId` is a real customer's uid. */
  cashierId?: string | null;
}): Record<string, unknown> {
  const profit = computeSaleProfit({
    grossSalesCentavos: params.subtotalCentavos,
    productCostCentavos: params.productCostCentavos,
    convenienceFeeCentavos: params.convenienceFeeCentavos,
  });

  return {
    orderId: params.orderId,
    paymentMethod: params.paymentMethod,
    grossSalesCentavos: params.subtotalCentavos,
    productCostCentavos: params.productCostCentavos,
    grossProfitCentavos: profit.grossProfitCentavos,
    convenienceFeeCentavos: params.convenienceFeeCentavos,
    netProfitCentavos: profit.netProfitCentavos,
    itemCount: params.itemCount,
    customerId: params.customerId,
    cashierId: params.cashierId ?? null,
    completedAt: Timestamp.fromDate(params.completedAt),
    dayKey: dayKeyFor(params.completedAt),
  };
}
