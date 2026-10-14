/// Build-time configuration, read from `--dart-define` flags.
///
/// Everything here is a compile-time constant so the values are baked into the binary and
/// tree-shaken: a release build cannot accidentally be pointed at an emulator, because the
/// emulator branch is not compiled into it.
///
/// ```powershell
/// flutter run --dart-define=USE_FIREBASE_EMULATOR=true
/// flutter run --dart-define=USE_MOCK_CATALOG=true
/// ```
abstract final class AppConfig {
  /// Connect Auth, Firestore, Functions and Storage to the local emulator suite.
  ///
  /// This is how the app is developed until a real Firebase project exists. It is
  /// deliberately opt-in: with no flag, the app talks to whatever project
  /// `firebase_options.dart` names.
  static const bool useFirebaseEmulator = bool.fromEnvironment(
    'USE_FIREBASE_EMULATOR',
  );

  /// Host the emulator suite is reachable at.
  ///
  /// `localhost` works for desktop and web. An Android emulator reaches the host machine
  /// at `10.0.2.2`; a physical device needs the machine's LAN address.
  static const String emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: 'localhost',
  );

  static const int authEmulatorPort = int.fromEnvironment(
    'AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );
  static const int firestoreEmulatorPort = int.fromEnvironment(
    'FIRESTORE_EMULATOR_PORT',
    defaultValue: 8080,
  );
  static const int functionsEmulatorPort = int.fromEnvironment(
    'FUNCTIONS_EMULATOR_PORT',
    defaultValue: 5001,
  );

  /// Region the Cloud Functions are deployed to. The SDK defaults to `us-central1`, so
  /// without this every callable would 404 against a function living elsewhere.
  static const String functionsRegion = 'asia-southeast1';
  static const int storageEmulatorPort = int.fromEnvironment(
    'STORAGE_EMULATOR_PORT',
    defaultValue: 9199,
  );

  /// Use the bundled local product catalog instead of the live external API.
  ///
  /// The mock exists so that product discovery and import can be developed and tested
  /// offline. It is never a silent fallback: when the live service fails at runtime the
  /// app says the catalog is unavailable rather than quietly serving mock data.
  static const bool useMockCatalog = bool.fromEnvironment('USE_MOCK_CATALOG');

  /// Base URL of the external product catalog.
  ///
  /// Open Food Facts is the default because it needs no API key and has usable coverage
  /// of Philippine barcodes. Swapping it for a paid catalog is a matter of pointing this
  /// at another host and writing one more `ProductCatalogService` implementation.
  static const String catalogBaseUrl = String.fromEnvironment(
    'CATALOG_BASE_URL',
    defaultValue: 'https://world.openfoodfacts.org',
  );

  /// How long any single external catalog request may take before it is abandoned.
  ///
  /// Short on purpose: an owner scanning a shelf must not wait on a slow third party, and
  /// the manual-entry fallback is always available.
  static const Duration catalogTimeout = Duration(seconds: 8);

  /// How long a Firestore or Functions call may take before the UI offers Retry.
  static const Duration backendTimeout = Duration(seconds: 20);

  /// Products fetched per page in the customer catalog.
  static const int catalogPageSize = 20;

  /// Rows fetched per page in owner lists (orders, inventory history, price history).
  static const int ownerListPageSize = 25;

  /// True when the build has no real Firebase project configured and is running against
  /// emulators. Used to show a persistent banner so a demo is never mistaken for live data.
  static bool get isDevelopmentBackend => useFirebaseEmulator;
}
