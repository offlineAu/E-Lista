/**
 * Order placement and status changes.
 *
 * This is the most security-sensitive code in the app, and it exists because of one rule:
 * the client's arithmetic is a preview, never a charge. `placeOrder` re-reads every
 * product, re-derives every price and the convenience fee from Firestore, checks stock and
 * decrements it — all inside a single Firestore transaction, so two customers racing for
 * the last pack cannot both win.
 */

import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  DEFAULT_GCASH_FEE_TIERS,
  normaliseGcashFeeTiers,
  resolveGcashFeeCentavos,
  type GcashFeeTier,
} from './domain/gcash_fees';
import { formatCentavos } from './domain/money';
import {
  asObject,
  dayKeyFor,
  db,
  gcashFeesDoc,
  optionalString,
  orderCostsDoc,
  paths,
  productPricingDoc,
  requireAuth,
  requireOwner,
  requireString,
} from './lib/context';

type PaymentMethod = 'cash' | 'gcash';

type OrderStatus =
  | 'pending'
  | 'confirmed'
  | 'preparing'
  | 'ready'
  | 'completed'
  | 'cancelled';

const OPEN_STATUSES: OrderStatus[] = ['pending', 'confirmed', 'preparing', 'ready'];

const ALLOWED_TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  pending: ['confirmed', 'cancelled'],
  confirmed: ['preparing', 'cancelled'],
  preparing: ['ready', 'cancelled'],
  ready: ['completed', 'cancelled'],
  completed: [],
  cancelled: [],
};

/** The most distinct products one order may contain. */
const MAX_ORDER_LINES = 50;

/** The most units of a single product one order may contain. */
const MAX_LINE_QUANTITY = 999;

interface RequestedLine {
  productId: string;
  quantity: number;
}

function parseRequestedLines(data: Record<string, unknown>): RequestedLine[] {
  const raw = data.items;
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new HttpsError('invalid-argument', 'Your cart is empty.');
  }
  if (raw.length > MAX_ORDER_LINES) {
    throw new HttpsError(
      'invalid-argument',
      `An order can hold at most ${MAX_ORDER_LINES} different products.`,
    );
  }

  const seen = new Set<string>();
  return raw.map((entry) => {
    if (typeof entry !== 'object' || entry === null) {
      throw new HttpsError('invalid-argument', 'Malformed cart item.');
    }
    const item = entry as Record<string, unknown>;
    const productId = item.productId;
    const quantity = item.quantity;

    if (typeof productId !== 'string' || productId.trim().length === 0) {
      throw new HttpsError('invalid-argument', 'Malformed cart item.');
    }
    if (
      typeof quantity !== 'number' ||
      !Number.isSafeInteger(quantity) ||
      quantity < 1 ||
      quantity > MAX_LINE_QUANTITY
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Each item needs a whole quantity of at least one.',
      );
    }
    if (seen.has(productId)) {
      throw new HttpsError('invalid-argument', 'The same product appears twice.');
    }
    seen.add(productId);

    return { productId: productId.trim(), quantity };
  });
}

function parsePaymentMethod(value: unknown): PaymentMethod {
  if (value === 'cash' || value === 'gcash') return value;
  throw new HttpsError('invalid-argument', 'Choose Cash or GCash.');
}

/** A short reference a customer can quote at the counter. */
function buildOrderNumber(now: Date): string {
  const day = dayKeyFor(now).replace(/-/g, '').slice(2); // yymmdd
  const suffix = Math.floor(Math.random() * 46656)
    .toString(36)
    .toUpperCase()
    .padStart(3, '0');
  return `EL-${day}-${suffix}`;
}

async function readFeeTiers(): Promise<GcashFeeTier[]> {
  const snapshot = await gcashFeesDoc().get();
  const data = snapshot.data();
  const raw = data?.tiers;
  if (!Array.isArray(raw) || raw.length === 0) {
    return normaliseGcashFeeTiers(DEFAULT_GCASH_FEE_TIERS);
  }
  return normaliseGcashFeeTiers(raw as GcashFeeTier[]);
}

/**
 * Places an order.
 *
 * The client sends what it wants to buy and, optionally, the total it showed the customer.
 * The server decides everything else. If the two totals disagree — because a price changed
 * between the cart being filled and Checkout being pressed — the order is refused with an
 * explanation rather than silently charging either figure.
 */
export const placeOrder = onCall(async (request) => {
  const caller = requireAuth(request);
  const data = asObject(request.data);

  const lines = parseRequestedLines(data);
  const paymentMethod = parsePaymentMethod(data.paymentMethod);
  const contactName = requireString(data, 'contactName', { maxLength: 120 });
  const contactPhone = requireString(data, 'contactPhone', { maxLength: 40 });
  const contactAddress = optionalString(data, 'contactAddress');
  const contactNotes = optionalString(data, 'contactNotes', { maxLength: 500 });

  const expectedTotal =
    typeof data.expectedTotalCentavos === 'number' &&
    Number.isSafeInteger(data.expectedTotalCentavos)
      ? data.expectedTotalCentavos
      : undefined;

  // Read outside the transaction: the fee table changes rarely and is not a race
  // participant, and keeping it out keeps the transaction's read set to the products.
  const feeTiers = await readFeeTiers();

  const orderRef = db.collection(paths.orders).doc();
  const now = new Date();

  const result = await db.runTransaction(async (transaction) => {
    // ---- reads ----------------------------------------------------------------
    const productRefs = lines.map((line) =>
      db.collection(paths.products).doc(line.productId),
    );
    const costRefs = lines.map((line) => productPricingDoc(line.productId));

    const productSnapshots = await transaction.getAll(...productRefs);
    const costSnapshots = await transaction.getAll(...costRefs);

    // ---- validate and price ---------------------------------------------------
    const orderItems: Record<string, unknown>[] = [];
    const costLines: Record<string, unknown>[] = [];
    const stockWrites: {
      ref: FirebaseFirestore.DocumentReference;
      previousStock: number;
      newStock: number;
      lowStockThreshold: number;
      productName: string;
      quantity: number;
    }[] = [];

    let subtotalCentavos = 0;
    let productCostCentavos = 0;
    let itemCount = 0;

    for (let index = 0; index < lines.length; index++) {
      const line = lines[index];
      const snapshot = productSnapshots[index];

      if (!snapshot.exists) {
        throw new HttpsError(
          'failed-precondition',
          'One of the products in your cart is no longer in the store. ' +
            'Please remove it and try again.',
        );
      }

      const product = snapshot.data() as Record<string, unknown>;
      const name = typeof product.name === 'string' ? product.name : 'Product';

      if (product.isActive !== true) {
        throw new HttpsError(
          'failed-precondition',
          `${name} is no longer available. Please remove it from your cart.`,
        );
      }

      const stock = Number(product.stockQuantity ?? 0);
      if (!Number.isSafeInteger(stock) || stock < line.quantity) {
        throw new HttpsError(
          'failed-precondition',
          stock <= 0
            ? `${name} has just sold out.`
            : `Only ${stock} of ${name} left. Please lower the quantity.`,
        );
      }

      // The price the store is charging right now, from the product document — never
      // from anything the client sent.
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

      // The cost snapshot goes to an owner-only subdocument, never onto the order the
      // customer can read.
      const costData = costSnapshots[index].data() as Record<string, unknown> | undefined;
      const unitCost = Number(costData?.costPriceCentavos ?? 0);
      const safeUnitCost = Number.isSafeInteger(unitCost) && unitCost >= 0 ? unitCost : 0;
      productCostCentavos += safeUnitCost * line.quantity;
      costLines.push({
        productId: line.productId,
        quantity: line.quantity,
        costPriceCentavos: safeUnitCost,
      });

      const threshold = Number(product.lowStockThreshold ?? 0);
      stockWrites.push({
        ref: productRefs[index],
        previousStock: stock,
        newStock: stock - line.quantity,
        lowStockThreshold: Number.isSafeInteger(threshold) ? threshold : 0,
        productName: name,
        quantity: line.quantity,
      });
    }

    const convenienceFeeCentavos =
      paymentMethod === 'gcash'
        ? resolveGcashFeeCentavos(subtotalCentavos, feeTiers)
        : 0;
    const totalCentavos = subtotalCentavos + convenienceFeeCentavos;

    if (expectedTotal !== undefined && expectedTotal !== totalCentavos) {
      throw new HttpsError(
        'failed-precondition',
        `The total changed to ${formatCentavos(totalCentavos)} while you were ` +
          'checking out. Please review your cart and confirm again.',
      );
    }

    // ---- writes ---------------------------------------------------------------
    for (const write of stockWrites) {
      transaction.update(write.ref, {
        stockQuantity: write.newStock,
        isLowStock: write.newStock <= write.lowStockThreshold,
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Stock is reserved at placement, not at completion: it is the only way two
      // customers cannot both buy the last pack. Cancelling gives it back.
      const ledgerRef = db.collection(paths.inventoryTransactions).doc();
      transaction.set(ledgerRef, {
        productId: write.ref.id,
        productName: write.productName,
        type: 'sale',
        quantity: -write.quantity,
        previousStock: write.previousStock,
        newStock: write.newStock,
        referenceType: 'order',
        referenceId: orderRef.id,
        performedBy: caller.uid,
        performedByName: contactName,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    const orderNumber = buildOrderNumber(now);

    transaction.set(orderRef, {
      orderNumber,
      customerId: caller.uid,
      customerType: caller.isAnonymous ? 'guest' : 'registered',
      paymentMethod,
      status: 'pending' satisfies OrderStatus,
      items: orderItems,
      subtotalCentavos,
      convenienceFeeCentavos,
      totalCentavos,
      itemCount,
      contact: {
        name: contactName,
        phoneNumber: contactPhone,
        address: contactAddress ?? null,
        notes: contactNotes ?? null,
      },
      statusHistory: [
        {
          status: 'pending',
          changedAt: Timestamp.fromDate(now),
          changedBy: caller.uid,
          note: null,
        },
      ],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      completedAt: null,
      cancelledAt: null,
      cancellationReason: null,
    });

    transaction.set(orderCostsDoc(orderRef.id), {
      lines: costLines,
      totalProductCostCentavos: productCostCentavos,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      orderId: orderRef.id,
      orderNumber,
      subtotalCentavos,
      convenienceFeeCentavos,
      totalCentavos,
    };
  });

  // The cart is cleared after the order is safely written, never before: a failed order
  // must not also cost the customer their basket.
  await db.collection(paths.carts).doc(caller.uid).set(
    { items: [], updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );

  return result;
});

/**
 * Moves an order along, or cancels it.
 *
 * Owner-only, and the allowed transitions are enforced here rather than in the owner's
 * screen. Two side effects matter:
 *
 * * **Cancelling returns the reserved stock**, with a ledger row for each product, so the
 *   shelf count stays honest.
 * * **Completing writes the sales record**, keyed by the order id so completing twice
 *   cannot double-count a day's takings.
 */
export const updateOrderStatus = onCall(async (request) => {
  const caller = requireOwner(request);
  const data = asObject(request.data);

  const orderId = requireString(data, 'orderId', { maxLength: 128 });
  const nextStatus = requireString(data, 'status', { maxLength: 32 }) as OrderStatus;
  const note = optionalString(data, 'note', { maxLength: 300 });

  if (!(nextStatus in ALLOWED_TRANSITIONS)) {
    throw new HttpsError('invalid-argument', 'Unknown order status.');
  }

  const orderRef = db.collection(paths.orders).doc(orderId);
  const now = new Date();

  return db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists) {
      throw new HttpsError('not-found', 'That order could not be found.');
    }

    const order = orderSnapshot.data() as Record<string, unknown>;
    const currentStatus = (order.status ?? 'pending') as OrderStatus;

    if (!ALLOWED_TRANSITIONS[currentStatus].includes(nextStatus)) {
      throw new HttpsError(
        'failed-precondition',
        `An order that is ${currentStatus} cannot be marked ${nextStatus}.`,
      );
    }

    const items = Array.isArray(order.items) ? order.items : [];

    // Reads must all happen before writes in a Firestore transaction, so gather anything
    // a cancellation or a completion needs up front.
    let costData: Record<string, unknown> | undefined;
    if (nextStatus === 'completed') {
      const costSnapshot = await transaction.get(orderCostsDoc(orderId));
      costData = costSnapshot.data() as Record<string, unknown> | undefined;
    }

    const restoreTargets: {
      ref: FirebaseFirestore.DocumentReference;
      snapshot: FirebaseFirestore.DocumentSnapshot;
      quantity: number;
      productName: string;
    }[] = [];

    if (nextStatus === 'cancelled' && OPEN_STATUSES.includes(currentStatus)) {
      for (const entry of items) {
        const item = entry as Record<string, unknown>;
        const productId = typeof item.productId === 'string' ? item.productId : null;
        const quantity = Number(item.quantity ?? 0);
        if (!productId || !Number.isSafeInteger(quantity) || quantity <= 0) continue;

        const ref = db.collection(paths.products).doc(productId);
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists) continue;

        restoreTargets.push({
          ref,
          snapshot,
          quantity,
          productName:
            typeof item.productName === 'string' ? item.productName : 'Product',
        });
      }
    }

    // ---- writes ---------------------------------------------------------------
    const statusHistory = Array.isArray(order.statusHistory)
      ? order.statusHistory
      : [];

    const updates: Record<string, unknown> = {
      status: nextStatus,
      updatedAt: FieldValue.serverTimestamp(),
      statusHistory: [
        ...statusHistory,
        {
          status: nextStatus,
          changedAt: Timestamp.fromDate(now),
          changedBy: caller.uid,
          note: note ?? null,
        },
      ],
    };

    if (nextStatus === 'completed') {
      updates.completedAt = Timestamp.fromDate(now);
    }
    if (nextStatus === 'cancelled') {
      updates.cancelledAt = Timestamp.fromDate(now);
      updates.cancellationReason = note ?? null;
    }

    transaction.update(orderRef, updates);

    for (const target of restoreTargets) {
      const product = target.snapshot.data() as Record<string, unknown>;
      const previousStock = Number(product.stockQuantity ?? 0);
      const newStock = previousStock + target.quantity;
      const threshold = Number(product.lowStockThreshold ?? 0);

      transaction.update(target.ref, {
        stockQuantity: newStock,
        isLowStock: newStock <= (Number.isSafeInteger(threshold) ? threshold : 0),
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.set(db.collection(paths.inventoryTransactions).doc(), {
        productId: target.ref.id,
        productName: target.productName,
        type: 'returned',
        quantity: target.quantity,
        previousStock,
        newStock,
        referenceType: 'order',
        referenceId: orderId,
        reason: note ?? 'Order cancelled',
        performedBy: caller.uid,
        performedByName: caller.name ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    if (nextStatus === 'completed') {
      const subtotal = Number(order.subtotalCentavos ?? 0);
      const fee = Number(order.convenienceFeeCentavos ?? 0);
      const productCost = Number(costData?.totalProductCostCentavos ?? 0);
      const grossProfit = subtotal - productCost;

      transaction.set(db.collection(paths.sales).doc(orderId), {
        orderId,
        paymentMethod: order.paymentMethod ?? 'cash',
        grossSalesCentavos: subtotal,
        productCostCentavos: productCost,
        grossProfitCentavos: grossProfit,
        convenienceFeeCentavos: fee,
        // The fee is money the customer paid on top of the goods; it is counted as
        // revenue here. What the store is charged by GCash in return is an expense the
        // app does not see, which is why reports call this "estimated".
        netProfitCentavos: grossProfit + fee,
        itemCount: Number(order.itemCount ?? 0),
        customerId: order.customerId ?? null,
        completedAt: Timestamp.fromDate(now),
        dayKey: dayKeyFor(now),
      });
    }

    return { orderId, status: nextStatus };
  });
});
