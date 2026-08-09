# Development

## Toolchain

| Tool | Version used | Notes |
| --- | --- | --- |
| Flutter | 3.44.9 (stable) | Installed at `D:\flutter` on this machine. |
| Dart | 3.12.2 | Bundled with Flutter. |
| Node | 22.15.0 | For `functions/` (Cloud Functions, TypeScript). |

Flutter is **not** on the system `PATH` on this machine. Either add `D:\flutter\bin` to
your `PATH`, or invoke it by full path:

```powershell
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat test
```

## Verification loop

```powershell
D:\flutter\bin\dart.bat format .
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat test
```

## Firebase

No Firebase project is configured yet. `lib/firebase_options.dart` holds placeholder
values and `lib/core/config/app_config.dart` decides at startup whether to connect to a
real project or to the local emulators.

### Running against emulators

```powershell
npm install -g firebase-tools     # once
firebase emulators:start          # from the repository root
```

Then run the app with the emulator flag:

```powershell
D:\flutter\bin\flutter.bat run --dart-define=USE_FIREBASE_EMULATOR=true
```

### Connecting a real project

```powershell
dart pub global activate flutterfire_cli
flutterfire configure --project <your-project-id>
```

This regenerates `lib/firebase_options.dart` and drops the platform config files
(`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`). Nothing else
in the app needs to change.

## Becoming the store owner

Roles live in the Firebase Auth custom claim `role`, which the Firestore rules read. The
first owner cannot be appointed by an existing owner, so `claimStoreOwnership` bootstraps
it with a one-time code:

```powershell
# Production
firebase functions:secrets:set OWNER_SETUP_CODE

# Emulator — functions/.secret.local (git-ignored)
OWNER_SETUP_CODE=dev-setup-code
```

Then, in the app: create an account with an email and password, open **Profile → I run this
store**, and enter the code. It works only while the store has no owner, so a leaked code
cannot be replayed later to mint a second one. After that, an owner grants access to others
from **Settings → Give someone owner access**.

A newly granted owner keeps their old ID token for up to an hour. The app forces a token
refresh immediately after the claim, which is why the dashboard appears without a restart.

## External product catalog

`ProductCatalogService` has two implementations:

- `OpenFoodFactsCatalogService` — live HTTP lookup, used when the app is online.
- `MockProductCatalogService` — a small local set of Philippine products, used in tests
  and when `--dart-define=USE_MOCK_CATALOG=true` is passed.

The store keeps working when the catalog is unreachable; only *discovery and import* of
new products degrades, and the UI says so explicitly.
