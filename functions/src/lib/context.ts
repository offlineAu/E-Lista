/**
 * Shared Firebase Admin setup, auth guards and collection paths.
 *
 * Everything financial in E-Lista happens behind a callable function, so this file is the
 * gate: it decides who is allowed to ask, and it is the only place the Admin SDK is
 * initialised.
 */

import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { Firestore, getFirestore } from 'firebase-admin/firestore';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

if (getApps().length === 0) {
  initializeApp();
}

export const db: Firestore = getFirestore();
export const auth = getAuth();

/** Firestore paths, in one place so a typo cannot silently create a new collection. */
export const paths = {
  users: 'users',
  products: 'products',
  categories: 'categories',
  orders: 'orders',
  carts: 'carts',
  sales: 'sales',
  inventoryTransactions: 'inventoryTransactions',
  productPriceHistory: 'productPriceHistory',
  productBatches: 'productBatches',
  settings: 'settings',
  cashCounts: 'cashCounts',
} as const;

/** The owner-only subdocument of a product, holding cost and pricing mode. */
export const productPricingDoc = (productId: string) =>
  db.collection(paths.products).doc(productId).collection('private').doc('pricing');

/** The owner-only subdocument of an order, holding the per-line cost snapshot. */
export const orderCostsDoc = (orderId: string) =>
  db.collection(paths.orders).doc(orderId).collection('private').doc('costs');

export const pricingSettingsDoc = () =>
  db.collection(paths.settings).doc('pricing');

export const gcashFeesDoc = () => db.collection(paths.settings).doc('gcash_fees');

export const gcashQrDoc = () => db.collection(paths.settings).doc('gcash_qr');

export interface Caller {
  uid: string;
  role: 'guest' | 'customer' | 'cashier' | 'owner';
  isAnonymous: boolean;
  name?: string;
}

/**
 * The signed-in caller, or an `unauthenticated` error.
 *
 * Anonymous users pass: guests are real users in this app and are allowed to place orders.
 * What they are not allowed to do is anything guarded by {@link requireOwner} or
 * {@link requireOwnerOrCashier}. An anonymous sign-in is always a guest regardless of any
 * role claim it happens to carry — `owner`/`cashier` only ever mean something for a real
 * credential.
 */
export function requireAuth(request: CallableRequest): Caller {
  const authContext = request.auth;
  if (!authContext) {
    throw new HttpsError('unauthenticated', 'Please sign in and try again.');
  }

  const token = authContext.token as Record<string, unknown>;
  const isAnonymous = token.firebase !== undefined &&
    (token.firebase as { sign_in_provider?: string }).sign_in_provider === 'anonymous';

  const claimedRole = token.role;
  const role = isAnonymous
    ? 'guest'
    : claimedRole === 'owner'
      ? 'owner'
      : claimedRole === 'cashier'
        ? 'cashier'
        : 'customer';

  return {
    uid: authContext.uid,
    role,
    isAnonymous,
    name: typeof token.name === 'string' ? token.name : undefined,
  };
}

/**
 * The caller, required to be the store owner.
 *
 * The check reads the `role` custom claim on the ID token — the same thing the Firestore
 * security rules check. A client cannot mint a claim, so this is a real boundary rather
 * than a client-side convention.
 */
export function requireOwner(request: CallableRequest): Caller {
  const caller = requireAuth(request);
  if (caller.role !== 'owner') {
    throw new HttpsError(
      'permission-denied',
      'Only the store owner can do that.',
    );
  }
  return caller;
}

/**
 * The caller, required to be the store owner or a cashier.
 *
 * For the functions a cashier is allowed to call: processing orders and recording stock
 * movements. Anything that changes a price, a cost, a setting, or another account's role
 * stays behind {@link requireOwner}.
 */
export function requireOwnerOrCashier(request: CallableRequest): Caller {
  const caller = requireAuth(request);
  if (caller.role !== 'owner' && caller.role !== 'cashier') {
    throw new HttpsError('permission-denied', 'Only store staff can do that.');
  }
  return caller;
}

/** Reads a required string field from callable data. */
export function requireString(
  data: Record<string, unknown>,
  field: string,
  { maxLength = 500 }: { maxLength?: number } = {},
): string {
  const value = data[field];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', `${field} is required.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw new HttpsError('invalid-argument', `${field} is too long.`);
  }
  return trimmed;
}

/** Reads an optional string field, normalising blanks to undefined. */
export function optionalString(
  data: Record<string, unknown>,
  field: string,
  { maxLength = 2000 }: { maxLength?: number } = {},
): string | undefined {
  const value = data[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', `${field} must be text.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) return undefined;
  if (trimmed.length > maxLength) {
    throw new HttpsError('invalid-argument', `${field} is too long.`);
  }
  return trimmed;
}

/** Reads an integer field, rejecting anything that is not a whole finite number. */
export function requireInt(
  data: Record<string, unknown>,
  field: string,
  { min = Number.MIN_SAFE_INTEGER, max = Number.MAX_SAFE_INTEGER }: {
    min?: number;
    max?: number;
  } = {},
): number {
  const value = data[field];
  if (typeof value !== 'number' || !Number.isSafeInteger(value)) {
    throw new HttpsError('invalid-argument', `${field} must be a whole number.`);
  }
  if (value < min || value > max) {
    throw new HttpsError(
      'invalid-argument',
      `${field} must be between ${min} and ${max}.`,
    );
  }
  return value;
}

export function optionalInt(
  data: Record<string, unknown>,
  field: string,
  options: { min?: number; max?: number } = {},
): number | undefined {
  if (data[field] === undefined || data[field] === null) return undefined;
  return requireInt(data, field, options);
}

/**
 * The one thing a price-history or batch write needs from a `WriteBatch` or a
 * `Transaction`.
 *
 * Their `set` overloads differ enough that a union of the two types is not callable, so the
 * capability is named directly. Both satisfy it structurally.
 */
export interface DocumentWriter {
  set(
    ref: FirebaseFirestore.DocumentReference,
    data: FirebaseFirestore.DocumentData,
  ): unknown;
}

/** Callable payloads arrive as `unknown`; this narrows them once, loudly. */
export function asObject(data: unknown): Record<string, unknown> {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'Malformed request.');
  }
  return data as Record<string, unknown>;
}

/** `2026-08-09` in the store's local day, used to group daily reports. */
export function dayKeyFor(date: Date, timeZoneOffsetHours = 8): string {
  // The Philippines is UTC+8 year-round with no daylight saving, so a fixed offset is
  // exact here rather than an approximation.
  const shifted = new Date(date.getTime() + timeZoneOffsetHours * 3600 * 1000);
  const year = shifted.getUTCFullYear();
  const month = `${shifted.getUTCMonth() + 1}`.padStart(2, '0');
  const day = `${shifted.getUTCDate()}`.padStart(2, '0');
  return `${year}-${month}-${day}`;
}
