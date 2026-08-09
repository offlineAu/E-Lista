# Security model

Two things in this app are worth attacking: the store's cost prices, and the totals
customers are charged. Everything below exists to protect one of them.

## Roles

A role lives in the Firebase Auth custom claim `role` on the user's ID token. Firestore
security rules read that claim; nothing else is authoritative.

- `users/{uid}.role` is a **mirror** for the UI. The rules reject any client write that
  changes it, and no rule anywhere trusts it.
- Only `claimStoreOwnership` and `setUserRole` — Cloud Functions using the Admin SDK — can
  set the claim. A client cannot mint one.
- Anonymous accounts are guests. They can shop, order and track; they are never owners.

Client-side route guards exist (`/owner/*` redirects a customer to the shop), but they are
**navigation, not security**. A customer who reaches an owner screen still cannot read a
single owner document, because every read is checked against the claim.

## Cost prices

Firestore grants access per document, never per field. A `products/{id}` document
containing `costPrice` could therefore never be made world-readable without leaking cost.
So it is split:

| Document | Contents | Who can read |
| --- | --- | --- |
| `products/{id}` | name, brand, image, cash + GCash prices, stock, unit | everyone |
| `products/{id}/private/pricing` | costPrice, pricingMode, profitPercentage | owner only |
| `orders/{id}` | items, prices paid, totals, contact | that customer, and the owner |
| `orders/{id}/private/costs` | per-line cost snapshot | owner only |
| `inventoryTransactions/*` | ledger, including receipt costs | owner only |
| `productPriceHistory/*` | cost and price trail | owner only |
| `sales/*` | revenue, cost, profit | owner only |
| `settings/pricing` | default profit percentage | owner only |
| `settings/gcash_fees` | convenience fee tiers | everyone (customers must see the fee) |

`test/models/product_test.dart` asserts that the public product map contains no cost or
profit field, so a future edit that reintroduced one would fail the build rather than
silently publish every supplier price in the store.

## Totals

The client computes a preview of prices, fees and totals so a shopper sees a number before
the round trip. It has no authority over any of them.

`placeOrder` is a callable Cloud Function. In a single Firestore transaction it:

1. re-reads every product in the cart,
2. rejects anything inactive or short of stock,
3. takes the unit price from the **product document**, never from the request,
4. resolves the GCash fee from `settings/gcash_fees` — once per order,
5. compares the result with the total the client says it displayed, and refuses the order
   with an explanation if they differ,
6. decrements stock and writes a ledger row for each line,
7. writes the order and its owner-only cost snapshot.

Because steps 2 and 6 are in one transaction, two customers racing for the last pack cannot
both succeed. Stock is reserved at placement, returned on cancellation, and consumed on
completion.

The rules deny client writes to `orders`, `products`, `inventoryTransactions`, `sales`,
`productPriceHistory` and `settings` outright, so there is no second path to any of this.

## What clients may write

Exactly one thing: `carts/{uid}`, and only their own. Everything in a cart is advisory —
`placeOrder` recomputes it all — which is what makes that write safe to allow.

## Deployment checklist

```powershell
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
firebase functions:secrets:set OWNER_SETUP_CODE   # before the first owner claims the store
```

The composite indexes in `firestore.indexes.json` correspond one-to-one with the queries in
`lib/repositories/`. Firestore rejects an unindexed composite query at runtime, so deploying
rules without indexes produces a working app with a broken catalog.
