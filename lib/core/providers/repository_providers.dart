import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/pricing/domain/gcash_fee_schedule.dart';
import '../../models/gcash_qr_settings.dart';
import '../../models/pricing_settings.dart';
import '../../repositories/cart_repository.dart';
import '../../repositories/category_repository.dart';
import '../../repositories/inventory_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/sales_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/gcash_qr_image_service.dart';
import '../../services/product_image_service.dart';
import '../../services/store_functions_service.dart';
import 'firebase_providers.dart';

/// The repositories, all built from the Firestore instance.
///
/// Every screen reaches data through one of these. A test overrides the repository
/// provider with a fake and never touches Firestore at all, which is why the repositories
/// are classes with interfaces worth faking rather than free functions over raw queries.

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(firestoreProvider));
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.watch(firestoreProvider));
});

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return CartRepository(ref.watch(firestoreProvider));
});

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(ref.watch(firestoreProvider));
});

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(firestoreProvider));
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(firestoreProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(firestoreProvider));
});

/// The callable Cloud Functions that own every financial write.
///
/// Kept alongside the repositories because callers treat it the same way: it is where a
/// screen goes to change something, just as a repository is where it goes to read.
final storeFunctionsProvider = Provider<StoreFunctionsService>((ref) {
  return StoreFunctionsService(ref.watch(firebaseFunctionsProvider));
});

/// Choosing and uploading product photos.
final productImageServiceProvider = Provider<ProductImageService>((ref) {
  return FirebaseProductImageService(ref.watch(firebaseStorageProvider));
});

/// Choosing and uploading the store's GCash QR code image.
final gcashQrImageServiceProvider = Provider<GcashQrImageService>((ref) {
  return FirebaseGcashQrImageService(ref.watch(firebaseStorageProvider));
});

/// The GCash convenience fee table.
///
/// Watched app-wide rather than fetched per checkout: the fee has to be shown in the cart,
/// on the checkout screen and in the confirmation, and all three must agree. A missing
/// document falls back to the default table, so a brand-new store still quotes a fee.
final gcashFeeScheduleProvider = StreamProvider<GcashFeeSchedule>((ref) {
  return ref.watch(settingsRepositoryProvider).watchGcashFees();
});

/// The store-wide pricing settings. Owner-only — the rules refuse this read for a
/// customer, which is why no customer screen watches it.
final pricingSettingsProvider = StreamProvider<PricingSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watchPricingSettings();
});

/// The store's GCash QR code, shown at checkout when GCash is selected. World-readable,
/// same reason as the fee table.
final gcashQrProvider = StreamProvider<GcashQrSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watchGcashQr();
});
