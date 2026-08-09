# E-Lista — Architecture

E-Lista is a personalized Sari-Sari Store application for Philippine users, built with
Flutter + Firebase. It serves two roles from a single binary: **customer** (including
unauthenticated guests) and **owner**.

## Decisions

| Concern | Choice | Reason |
| --- | --- | --- |
| State management | `flutter_riverpod` (no codegen) | One approach everywhere; testable, compile-safe overrides for fakes. |
| Routing | `go_router` with a redirect guard | Role/auth guards live in one place; deep links work. |
| Money | `Money` value type over `int` centavos | No binary floating point anywhere in financial math. |
| Percentages | `Percentage` value type over `int` basis points | `20.5%` is exactly representable; no `0.205` drift. |
| Backend | Firebase only | Firestore + Auth + Storage + Cloud Functions. No separate server. |
| Server authority | Callable Cloud Functions for anything financial | Clients never write orders, stock, sales, or prices directly. |
| External catalog | `ProductCatalogService` interface | Swappable; the app is fully usable when it is down. |

## Layers

```
lib/
  core/         constants, theme, money/percentage, errors, result types, utils
  models/       Firestore entities (immutable, explicit (de)serialisation)
  repositories/ Firestore access — the only place FirebaseFirestore is touched
  services/     cross-cutting services (auth, catalog, scanner, connectivity)
  features/     one folder per feature: presentation widgets + Riverpod controllers
  widgets/      shared presentation widgets
  routing/      route table + guards
```

Business rules (pricing, fee tiers, inventory maths, order totals) live in `core/` and
`services/` as pure Dart so they can be unit-tested without Flutter or Firebase, and so
the same code can be mirrored by the Cloud Functions implementation.

## Cost-price protection

Firestore security rules grant or deny access per **document**, not per field. A single
`products/{id}` document containing `costPrice` could therefore never be made readable by
customers without leaking cost. The data model splits accordingly:

```
products/{productId}                  # public: name, brand, prices customers pay, stock
products/{productId}/private/pricing  # owner only: costPrice, pricingMode, profitPercentage

orders/{orderId}                      # customer-readable (own orders only)
orders/{orderId}/private/costs        # owner only: per-line cost snapshot for profit maths
```

The same rule applies to `sales`, `productPriceHistory`, `inventoryTransactions` and
`settings/pricing` — all owner-only collections.

`settings/gcash_fees` is public-read (customers must preview the convenience fee at
checkout) and owner-write.

## Server-side authority

These operations are callable Cloud Functions; the corresponding client writes are denied
by rules:

- `placeOrder` — re-reads every product, re-derives every price and the GCash fee from
  server state, checks stock, decrements stock atomically, writes the order and the
  inventory transactions in one Firestore transaction. The client-supplied total is used
  only to detect a mismatch, never to charge.
- `updateOrderStatus` — owner-only status transitions; on `completed` it writes the sales
  record, on `cancelled` it returns reserved stock.
- `saveProduct` / `adjustInventory` / `savePricingSettings` / `saveGcashTiers` — owner-only
  mutations that recompute derived prices and append history rows.

## Configuration required before release

`lib/firebase_options.dart` is a placeholder. Run:

```
dart pub global activate flutterfire_cli
flutterfire configure --project <your-project-id>
```

Until then the app runs against the Firebase Emulator Suite — see `docs/DEVELOPMENT.md`.
