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

import { batchDoc } from './lib/batches';
import {
  buildSaleRecord,
  priceAndAllocateLines,
  readPricingSnapshots,
  writeStockForSale,
} from './lib/order_lines';
import {
  DEFAULT_GCASH_FEE_TIERS,
  normaliseGcashFeeTiers,
  resolveGcashFeeCentavos,
  type GcashFeeTier,
} from './domain/gcash_fees';
import { resolveTender, TenderError } from './domain/tender';
import { formatCentavos } from './domain/money';
import {
  asObject,
  dayKeyFor,
  db,
  gcashFeesDoc,
  optionalString,
  orderCostsDoc,
  paths,
  requireAuth,
  requireOwnerOrCashier,
  requireString,
} from './lib/context';

type PaymentMethod = 'cash' | 'gcash';

/** Which side of the counter created the order: a customer's own cart, or a cashier
 *  ringing up a walk-in sale with no customer account involved. */
type OrderChannel = 'storefront' | 'pos';

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
    const reads = await readPricingSnapshots(transaction, lines);
    const priced = priceAndAllocateLines({ lines, paymentMethod, ...reads });

    const convenienceFeeCentavos =
      paymentMethod === 'gcash'
        ? resolveGcashFeeCentavos(priced.subtotalCentavos, feeTiers)
        : 0;
    const totalCentavos = priced.subtotalCentavos + convenienceFeeCentavos;

    if (expectedTotal !== undefined && expectedTotal !== totalCentavos) {
      throw new HttpsError(
        'failed-precondition',
        `The total changed to ${formatCentavos(totalCentavos)} while you were ` +
          'checking out. Please review your cart and confirm again.',
      );
    }

    // Stock is reserved at placement, not at completion: it is the only way two customers
    // cannot both buy the last pack. Cancelling gives it back.
    writeStockForSale(transaction, {
      stockWrites: priced.stockWrites,
      orderId: orderRef.id,
      performedBy: caller.uid,
      performedByName: contactName,
    });

    const orderNumber = buildOrderNumber(now);

    transaction.set(orderRef, {
      orderNumber,
      channel: 'storefront' satisfies OrderChannel,
      customerId: caller.uid,
      customerType: caller.isAnonymous ? 'guest' : 'registered',
      paymentMethod,
      status: 'pending' satisfies OrderStatus,
      items: priced.orderItems,
      subtotalCentavos: priced.subtotalCentavos,
      convenienceFeeCentavos,
      totalCentavos,
      itemCount: priced.itemCount,
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
      lines: priced.costLines,
      totalProductCostCentavos: priced.productCostCentavos,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      orderId: orderRef.id,
      orderNumber,
      subtotalCentavos: priced.subtotalCentavos,
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
 * Owner or cashier — this is what "processing sales/orders" means at the register — and the
 * allowed transitions are enforced here rather than in the owner's screen. Two side effects
 * matter:
 *
 * * **Cancelling returns the reserved stock**, with a ledger row for each product, so the
 *   shelf count stays honest.
 * * **Completing writes the sales record**, keyed by the order id so completing twice
 *   cannot double-count a day's takings.
 */
export const updateOrderStatus = onCall(async (request) => {
  const caller = requireOwnerOrCashier(request);
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
    // a cancellation or a completion needs up front. Cancellation needs the cost snapshot
    // too now: it records exactly which batches the sale drew from, which is what lets a
    // cancellation restore those specific batches instead of a flat product-level pool.
    let costData: Record<string, unknown> | undefined;
    if (nextStatus === 'completed' || nextStatus === 'cancelled') {
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

    if (nextStatus === 'cancelled' && OPEN_STATUSES.includes(currentStatus)) {
      // The flat stockQuantity restore above always happens, for every unit, regardless of
      // batch attribution — this only puts the units back into the *specific* batches the
      // sale actually drew from, so a batch fully sold out by this order becomes sellable
      // (and FEFO-eligible) again rather than the return silently landing wherever is
      // oldest now.
      const costLines = Array.isArray(costData?.lines) ? costData!.lines : [];
      for (const entry of costLines) {
        const line = entry as Record<string, unknown>;
        const batches = Array.isArray(line.batches) ? line.batches : [];
        for (const draw of batches) {
          const batchDraw = draw as Record<string, unknown>;
          const batchId = batchDraw.batchId;
          const quantity = Number(batchDraw.quantity ?? 0);
          if (typeof batchId !== 'string' || !Number.isSafeInteger(quantity) || quantity <= 0) {
            continue;
          }
          transaction.update(batchDoc(batchId), {
            remainingQuantity: FieldValue.increment(quantity),
          });
        }
      }
    }

    if (nextStatus === 'completed') {
      transaction.set(
        db.collection(paths.sales).doc(orderId),
        buildSaleRecord({
          orderId,
          paymentMethod: (order.paymentMethod as PaymentMethod) ?? 'cash',
          subtotalCentavos: Number(order.subtotalCentavos ?? 0),
          convenienceFeeCentavos: Number(order.convenienceFeeCentavos ?? 0),
          productCostCentavos: Number(costData?.totalProductCostCentavos ?? 0),
          itemCount: Number(order.itemCount ?? 0),
          customerId: (order.customerId as string | null) ?? null,
          completedAt: now,
        }),
      );
    }

    return { orderId, status: nextStatus };
  });
});

/**
 * Books a walk-in register sale as already complete.
 *
 * No cart, no contact, no status ladder: a customer at the counter has already paid before
 * the cashier presses anything, so the order is written straight to `completed` in one
 * transaction rather than started `pending` and walked through {@link updateOrderStatus}
 * four times. Owner or cashier only — a plain customer account must never be able to mint a
 * completed, stock-decrementing sale for itself.
 */
export const placeWalkInSale = onCall(async (request) => {
  const caller = requireOwnerOrCashier(request);
  const data = asObject(request.data);

  const lines = parseRequestedLines(data);
  const paymentMethod = parsePaymentMethod(data.paymentMethod);
  const customerName = optionalString(data, 'customerName', { maxLength: 120 });
  const rawTendered =
    typeof data.amountTenderedCentavos === 'number' ? data.amountTenderedCentavos : undefined;

  const expectedTotal =
    typeof data.expectedTotalCentavos === 'number' &&
    Number.isSafeInteger(data.expectedTotalCentavos)
      ? data.expectedTotalCentavos
      : undefined;

  // Read outside the transaction, same as placeOrder: the fee table changes rarely and is
  // not a race participant.
  const feeTiers = await readFeeTiers();

  const orderRef = db.collection(paths.orders).doc();
  const now = new Date();

  return db.runTransaction(async (transaction) => {
    const reads = await readPricingSnapshots(transaction, lines);
    const priced = priceAndAllocateLines({ lines, paymentMethod, ...reads });

    const convenienceFeeCentavos =
      paymentMethod === 'gcash'
        ? resolveGcashFeeCentavos(priced.subtotalCentavos, feeTiers)
        : 0;
    const totalCentavos = priced.subtotalCentavos + convenienceFeeCentavos;

    if (expectedTotal !== undefined && expectedTotal !== totalCentavos) {
      throw new HttpsError(
        'failed-precondition',
        `The total changed to ${formatCentavos(totalCentavos)} while ringing this up. ` +
          'Please review the sale and confirm again.',
      );
    }

    let tender;
    try {
      tender = resolveTender({
        paymentMethod,
        totalCentavos,
        amountTenderedCentavos: rawTendered,
      });
    } catch (error) {
      if (error instanceof TenderError) {
        throw new HttpsError('invalid-argument', error.message);
      }
      throw error;
    }

    writeStockForSale(transaction, {
      stockWrites: priced.stockWrites,
      orderId: orderRef.id,
      performedBy: caller.uid,
      performedByName: caller.name ?? 'Staff',
    });

    const orderNumber = buildOrderNumber(now);

    transaction.set(orderRef, {
      orderNumber,
      channel: 'pos' satisfies OrderChannel,
      // A walk-in sale has no customer account; `customerId` here has always actually held
      // the ringing-up cashier's uid, which `cashierId` now says explicitly. Both stay,
      // additive rather than a breaking rename.
      customerId: caller.uid,
      cashierId: caller.uid,
      customerType: caller.isAnonymous ? 'guest' : 'registered',
      paymentMethod,
      status: 'completed' satisfies OrderStatus,
      items: priced.orderItems,
      subtotalCentavos: priced.subtotalCentavos,
      convenienceFeeCentavos,
      totalCentavos,
      itemCount: priced.itemCount,
      amountTenderedCentavos: tender.amountTenderedCentavos,
      changeCentavos: tender.changeCentavos,
      contact: {
        name: customerName ?? 'Walk-in customer',
        phoneNumber: '',
        address: null,
        notes: null,
      },
      statusHistory: [
        {
          status: 'completed',
          changedAt: Timestamp.fromDate(now),
          changedBy: caller.uid,
          note: null,
        },
      ],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      completedAt: Timestamp.fromDate(now),
      cancelledAt: null,
      cancellationReason: null,
    });

    transaction.set(orderCostsDoc(orderRef.id), {
      lines: priced.costLines,
      totalProductCostCentavos: priced.productCostCentavos,
      createdAt: FieldValue.serverTimestamp(),
    });

    transaction.set(
      db.collection(paths.sales).doc(orderRef.id),
      buildSaleRecord({
        orderId: orderRef.id,
        paymentMethod,
        subtotalCentavos: priced.subtotalCentavos,
        convenienceFeeCentavos,
        productCostCentavos: priced.productCostCentavos,
        itemCount: priced.itemCount,
        customerId: caller.uid,
        cashierId: caller.uid,
        completedAt: now,
      }),
    );

    return {
      orderId: orderRef.id,
      orderNumber,
      subtotalCentavos: priced.subtotalCentavos,
      convenienceFeeCentavos,
      totalCentavos,
      amountTenderedCentavos: tender.amountTenderedCentavos,
      changeCentavos: tender.changeCentavos,
    };
  });
});
