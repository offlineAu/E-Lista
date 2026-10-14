import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_mapper.dart';
import 'product_image_service.dart';

/// Choosing and uploading the store's GCash "Scan to Pay" QR code.
///
/// The same shape as [ProductImageService] — pick, then upload — but for one fixed image
/// rather than one per product: there is only ever a single QR code for the whole store, so
/// the storage path has no id in it and a re-upload simply replaces it.
abstract interface class GcashQrImageService {
  bool get isSupported;

  Future<PickedProductImage?> pick({required bool fromCamera});

  /// Uploads the QR image and returns the URL to store in `settings/gcash_qr`.
  Future<String> upload(PickedProductImage image);
}

class FirebaseGcashQrImageService implements GcashQrImageService {
  FirebaseGcashQrImageService(this._storage, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final FirebaseStorage _storage;
  final ImagePicker _picker;

  static const double _maxDimension = 1024;
  static const int _quality = 82;

  /// Matches the ceiling in `storage.rules`.
  static const int _maxUploadBytes = 5 * 1024 * 1024;

  @override
  bool get isSupported => true;

  @override
  Future<PickedProductImage?> pick({required bool fromCamera}) {
    return ErrorMapper.guard(() async {
      final file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
        imageQuality: _quality,
      );
      if (file == null) return null;

      final bytes = await file.readAsBytes();
      if (bytes.length > _maxUploadBytes) {
        throw const AppFailure.invalidInput(
          'That image is too large. Please choose one under 5 MB.',
        );
      }
      return PickedProductImage(bytes: bytes, fileName: file.name);
    }, operation: 'choose the QR code image');
  }

  @override
  Future<String> upload(PickedProductImage image) {
    return ErrorMapper.guard(() async {
      final extension = _extensionOf(image.fileName);
      // A fixed path, not one per id: there is only ever one QR code for the whole store,
      // so re-uploading replaces it rather than leaving orphans in the bucket.
      final reference = _storage.ref('settings/gcash_qr/qr$extension');

      await reference.putData(
        image.bytes,
        SettableMetadata(contentType: _contentTypeFor(extension)),
      );
      return reference.getDownloadURL();
    }, operation: 'upload the QR code');
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return '.jpg';
    final extension = fileName.substring(dot).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
        ? extension
        : '.jpg';
  }

  static String _contentTypeFor(String extension) => switch (extension) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}
