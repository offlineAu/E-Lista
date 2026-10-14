import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/error_mapper.dart';
import '../features/pricing/domain/gcash_fee_schedule.dart';
import '../models/gcash_qr_settings.dart';
import '../models/pricing_settings.dart';

/// Reads the store's pricing configuration from `settings/*`.
///
/// The two documents have deliberately different visibility:
///
/// * `settings/pricing` — the default profit percentage. Owner-only: it is business
///   information, and no customer screen needs it to display a price, because prices are
///   already materialised on each product.
/// * `settings/gcash_fees` — the convenience fee tiers. World-readable, because a customer
///   must be able to see the fee that will be added before they confirm an order.
/// * `settings/gcash_qr` — the store's GCash "Scan to Pay" QR code image. World-readable,
///   same reason as the fee tiers.
///
/// Writes go through Cloud Functions, which revalidate and re-price affected products;
/// this class only reads.
class SettingsRepository {
  SettingsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collectionPath = 'settings';
  static const String pricingDocumentId = 'pricing';
  static const String gcashFeesDocumentId = 'gcash_fees';
  static const String gcashQrDocumentId = 'gcash_qr';

  DocumentReference<Map<String, Object?>> get _pricingDocument =>
      _firestore.collection(collectionPath).doc(pricingDocumentId);

  DocumentReference<Map<String, Object?>> get _gcashFeesDocument =>
      _firestore.collection(collectionPath).doc(gcashFeesDocumentId);

  DocumentReference<Map<String, Object?>> get _gcashQrDocument =>
      _firestore.collection(collectionPath).doc(gcashQrDocumentId);

  /// Streams the store-wide pricing settings, falling back to the defaults while the
  /// document does not exist.
  Stream<PricingSettings> watchPricingSettings() {
    return _pricingDocument.snapshots().map(
      (snapshot) => PricingSettings.fromJson(snapshot.data()),
    );
  }

  Future<PricingSettings> fetchPricingSettings() {
    return ErrorMapper.guard(() async {
      final snapshot = await _pricingDocument.get();
      return PricingSettings.fromJson(snapshot.data());
    }, operation: 'load pricing settings');
  }

  /// Streams the GCash fee table.
  ///
  /// A store that has never opened Pricing Settings still needs a fee table, so a missing
  /// document reads as [GcashFeeSchedule.defaultSchedule] rather than as an error. A
  /// *malformed* document is a different matter and is allowed to throw: charging an
  /// unknown fee would be worse than refusing to check out.
  Stream<GcashFeeSchedule> watchGcashFees() {
    return _gcashFeesDocument.snapshots().map(_readSchedule);
  }

  Future<GcashFeeSchedule> fetchGcashFees() {
    return ErrorMapper.guard(() async {
      final snapshot = await _gcashFeesDocument.get();
      return _readSchedule(snapshot);
    }, operation: 'load the GCash fees');
  }

  static GcashFeeSchedule _readSchedule(
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return GcashFeeSchedule.defaultSchedule;
    return GcashFeeSchedule.fromJson(data['tiers']);
  }

  /// Streams the store's GCash QR code, or [GcashQrSettings.none] before the owner has
  /// uploaded one.
  Stream<GcashQrSettings> watchGcashQr() {
    return _gcashQrDocument.snapshots().map(
      (snapshot) => GcashQrSettings.fromJson(snapshot.data()),
    );
  }
}
