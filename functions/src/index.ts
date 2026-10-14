/**
 * E-Lista Cloud Functions.
 *
 * These are the store's server-side authority. The Firestore rules deny client writes to
 * orders, products, inventory, sales and settings, so every one of those changes arrives
 * here, where it can be validated against what is actually in the database rather than
 * against what a client claims.
 *
 * The division of labour:
 *
 *   placeOrder            re-prices the cart, checks and reserves stock, writes the order
 *   updateOrderStatus     moves an order along; returns stock on cancel, books the sale on
 *                         completion
 *   placeWalkInSale       rings up a counter sale with no customer account, booked complete
 *                         immediately, with cash tender/change or GCash
 *   saveProduct           derives selling prices from cost and profit, appends price history
 *   setProductActive      hides a product without deleting the history that references it
 *   adjustInventory       restocks, adjustments, damage, expiry and returns, each with a
 *                         ledger row
 *   savePricingSettings   changes the store default profit and re-prices what follows it
 *   saveGcashFeeTiers     validates and stores the convenience fee table
 *   saveGcashQr           sets or clears the store's GCash "Scan to Pay" QR code image
 *   recordCashCount       logs an end-of-shift cash-drawer count against what was expected
 *   seedStore             writes the documents a brand-new store needs
 *   claimStoreOwnership   appoints the first owner, once, with a setup code
 *   setUserRole           grants or revokes owner access afterwards
 */

import { setGlobalOptions } from 'firebase-functions/v2';

// Asia-Southeast is the closest region to the Philippines; running here keeps a checkout
// round trip on a mobile connection noticeably shorter than a US default would.
setGlobalOptions({
  region: 'asia-southeast1',
  maxInstances: 10,
});

export { placeOrder, updateOrderStatus, placeWalkInSale } from './orders';
export { saveProduct, setProductActive } from './products';
export { adjustInventory } from './inventory';
export {
  savePricingSettings,
  saveGcashFeeTiers,
  saveGcashQr,
  seedStore,
} from './settings';
export { claimStoreOwnership, setUserRole } from './roles';
export { recordCashCount } from './shifts';
