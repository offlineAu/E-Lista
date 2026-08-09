import 'package:firebase_storage/firebase_storage.dart';
// `foundation` re-exports `Uint8List`, so `dart:typed_data` is not needed as well.
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_mapper.dart';

/// A photo the owner chose but has not uploaded yet.
///
/// Held as bytes rather than as a file path so the same code works on the web, where there
/// is no file system to point at.
@immutable
class PickedProductImage {
  const PickedProductImage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;

  int get sizeInBytes => bytes.length;
}

/// Choosing and uploading product photos.
///
/// Wrapped as a service for the same reason as the scanner: a camera and a storage bucket
/// are both unavailable in a widget test, and the UI should not have to know that.
abstract interface class ProductImageService {
  /// Whether photos can be chosen on this device at all.
  bool get isSupported;

  /// Opens the camera or the gallery. Returns `null` if the owner backed out.
  Future<PickedProductImage?> pick({required bool fromCamera});

  /// Uploads a photo and returns the URL to store on the product.
  Future<String> upload(PickedProductImage image, {required String productId});
}

/// The real implementation: `image_picker` for choosing, Firebase Storage for keeping.
class FirebaseProductImageService implements ProductImageService {
  FirebaseProductImageService(this._storage, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final FirebaseStorage _storage;
  final ImagePicker _picker;

  /// Product photos are shown at most a few hundred pixels wide, and a store's connection
  /// is usually a mobile one. Downscaling before upload is the difference between a 4 MB
  /// original and a ~150 KB image that looks identical on a shelf card.
  static const double _maxDimension = 1024;
  static const int _quality = 82;

  /// Matches the ceiling in `storage.rules`, so an oversized file is refused here with a
  /// sentence rather than by the bucket with a code.
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
          'That photo is too large. Please choose one under 5 MB.',
        );
      }
      return PickedProductImage(bytes: bytes, fileName: file.name);
    }, operation: 'choose a photo');
  }

  @override
  Future<String> upload(PickedProductImage image, {required String productId}) {
    return ErrorMapper.guard(() async {
      final extension = _extensionOf(image.fileName);
      // The path is stable per product, so re-uploading replaces the old photo instead
      // of leaving orphans in the bucket that nothing will ever clean up.
      final reference = _storage.ref('products/$productId/photo$extension');

      await reference.putData(
        image.bytes,
        SettableMetadata(contentType: _contentTypeFor(extension)),
      );
      return reference.getDownloadURL();
    }, operation: 'upload the photo');
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
