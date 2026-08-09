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
 *   saveProduct           derives selling prices from cost and profit, appends price history
 *   setProductActive      hides a product without deleting the history that references it
 *   adjustInventory       restocks, adjustments, damage, expiry and returns, each with a
 *                         ledger row
 *   savePricingSettings   changes the store default profit and re-prices what follows it
 *   saveGcashFeeTiers     validates and stores the convenience fee table
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

export { placeOrder, updateOrderStatus } from './orders';
export { saveProduct, setProductActive } from './products';
export { adjustInventory } from './inventory';
export { savePricingSettings, saveGcashFeeTiers, seedStore } from './settings';
export { claimStoreOwnership, setUserRole } from './roles';
