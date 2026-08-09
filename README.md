# E-Lista

A sari-sari store app for Philippine neighbourhood shops, built with Flutter and Firebase.
One binary serves two roles: shoppers — including guests who never make an account — and
the store owner, who prices, restocks and fulfils.

## What it does

**For the shopper**

Open the app and start browsing; there is no sign-up wall. Search by name, brand, category
or the barcode on the pack, scan a product to see what it costs, fill a cart, and check out
with cash or GCash. Order status is trackable from the moment it is placed. Guests get all
of this, and can turn their session into a real account afterwards without losing their
cart or their order history.

**For the owner**

A dashboard with today's takings, today's estimated profit, orders waiting and products
running low. Products are added by scanning a barcode and importing the description, by
searching an external catalog, or by hand. Restocking is a continuous scan-and-count loop
built for working through a delivery. Stock changes are a ledger, not a number. Pricing is
policy-driven: set a profit percentage once and every product follows it, unless it is
pinned to its own.

## The pricing rules

The two payment methods price differently, on purpose.

**Cash uses a markup, floored to a whole peso.** `floor(cost × (1 + markup))`. ₱15 at 20%
is ₱18; ₱17 at 20% works out to ₱20.40 and is sold at ₱20. Never ₱21, never ₱20.40 — cash
in a sari-sari store is counted in coins.

**GCash uses a true margin, keeping centavos.** `cost ÷ (1 − margin)`. ₱15 at 20% is
₱18.75, of which exactly ₱3.75 is profit. The centavos are what make the margin true.

**The GCash convenience fee is charged once per order**, never per item, from a tier table
the owner edits. An order of ₱18.75 × 2 plus ₱25.00 has a subtotal of ₱62.50, falls in the
₱0–₱99.99 band, and pays ₱0.50 once: ₱63.00.

Every peso in the app is an integer number of centavos and every percentage an integer
number of basis points. No financial value is ever a `double`.

## How it is kept honest

- **Cost prices are unreadable by customers.** Firestore grants access per document, so
  cost, profit percentage and pricing mode live in `products/{id}/private/pricing`, which
  the rules serve only to an owner. The same split keeps per-line costs off the orders a
  customer can read.
- **The client never decides what anyone pays.** Checkout sends a cart and the total it
  displayed; `placeOrder` re-reads every product, re-derives every price and the fee, and
  refuses the order if the two disagree.
- **Stock cannot be oversold.** It is checked and decremented inside one Firestore
  transaction, with a ledger row written in the same transaction.
- **Historical prices never move.** Orders store a snapshot. Re-pricing a product tomorrow
  cannot change what an order from today says it cost.
- **The external catalog is optional.** It supplies names and pictures for products the
  store has never carried, and nothing else — never a price. When it is unreachable, the
  store keeps working and the app says so instead of pretending.

## Running it

Flutter 3.44.9 / Dart 3.12.2. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the
toolchain, the emulator setup and the verification loop, and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is laid out and why.

No Firebase project is wired up yet — `lib/firebase_options.dart` is a documented
placeholder that runs against the local emulator suite and refuses to pretend otherwise.
Connecting a real project is one `flutterfire configure` away.

```powershell
firebase emulators:start
D:\flutter\bin\flutter.bat run --dart-define=USE_FIREBASE_EMULATOR=true
```

## Layout

```
lib/            Flutter app — core, models, repositories, services, features, widgets
functions/      Cloud Functions (TypeScript): the server-side authority
firestore.rules Security rules enforcing the role and cost-price boundaries
test/           Dart tests
docs/           Architecture and development notes
```
