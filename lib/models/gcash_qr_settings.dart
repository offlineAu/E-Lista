import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

/// The store's GCash "Scan to Pay" QR code, at `settings/gcash_qr`.
///
/// A static image the owner uploads once — the same QR their own GCash app already
/// generates under Profile → My QR Code — not something this app generates itself. Public
/// read, same as `settings/gcash_fees`: a customer paying by GCash has to be able to see it.
@immutable
class GcashQrSettings {
  const GcashQrSettings({this.imageUrl, this.updatedAt, this.updatedBy});

  static const GcashQrSettings none = GcashQrSettings();

  /// `null` until the owner uploads one, or after they remove it.
  final String? imageUrl;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get hasImage => imageUrl?.isNotEmpty ?? false;

  static GcashQrSettings fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) return none;
    return GcashQrSettings(
      imageUrl: json['imageUrl'] as String?,
      updatedAt: switch (json['updatedAt']) {
        Timestamp() => (json['updatedAt']! as Timestamp).toDate(),
        _ => null,
      },
      updatedBy: json['updatedBy'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GcashQrSettings && other.imageUrl == imageUrl;

  @override
  int get hashCode => imageUrl.hashCode;

  @override
  String toString() => 'GcashQrSettings(hasImage: $hasImage)';
}
