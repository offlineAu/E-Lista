import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Wraps the camera scanner so the rest of the app never imports `mobile_scanner`.
///
/// The abstraction earns its place twice over: the scanner cannot run in a widget test or
/// on a machine with no camera, and barcode plugins are the part of a Flutter app most
/// likely to need replacing. Screens depend on this interface, so a swap is one file.
abstract interface class BarcodeScannerService {
  /// Whether this device can scan at all. False on the web build and on desktops with no
  /// camera, where the UI offers manual entry instead of a dead viewfinder.
  bool get isSupported;

  /// A controller for the camera preview, or `null` when scanning is unsupported.
  ///
  /// Typed as `Object?` so that no file outside this one has to know the plugin's types;
  /// the scanner widget casts it back.
  Object? createController();

  /// Normalises a raw scan into a barcode this app will accept.
  ///
  /// Returns `null` for anything that is not a retail barcode — QR codes on posters,
  /// misreads, a loyalty card — so the caller can ignore it rather than creating a product
  /// that can never be scanned again.
  String? normalise(String? rawValue);
}

/// The real scanner, backed by `mobile_scanner`.
class MobileBarcodeScannerService implements BarcodeScannerService {
  const MobileBarcodeScannerService();

  @override
  bool get isSupported {
    // The plugin supports the web, but a browser's camera permission model makes it an
    // unreliable primary path for a shopkeeper working through a shelf. Mobile is where
    // scanning is offered; elsewhere the UI leads with typing the number.
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Object? createController() {
    if (!isSupported) return null;
    return MobileScannerController(
      // Retail barcodes only. Accepting QR would let a poster or a payment code be read
      // as a product.
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.itf14,
        BarcodeFormat.code128,
      ],
      detectionSpeed: DetectionSpeed.normal,
      // The scanner is used at arm's length against a shelf; the back camera focuses
      // closer and reads small print better than a wide-angle at speed.
      facing: CameraFacing.back,
    );
  }

  @override
  String? normalise(String? rawValue) => normaliseBarcode(rawValue);
}

/// A scanner for tests and for platforms with no camera.
///
/// [scripted] values are handed out in order by [nextScan], which lets a test drive the
/// continuous restock flow without a camera.
class FakeBarcodeScannerService implements BarcodeScannerService {
  FakeBarcodeScannerService({
    this.scripted = const [],
    this.isSupported = true,
  });

  final List<String> scripted;
  int _index = 0;

  @override
  final bool isSupported;

  @override
  Object? createController() => null;

  @override
  String? normalise(String? rawValue) => normaliseBarcode(rawValue);

  /// The next scripted scan, or `null` when the script is exhausted.
  String? nextScan() {
    if (_index >= scripted.length) return null;
    return scripted[_index++];
  }
}

/// Turns a raw scan into an acceptable barcode, or `null`.
///
/// Retail barcodes are 8–14 digits: EAN-8, UPC-E, UPC-A, EAN-13 and ITF-14. A scanner will
/// happily read a QR code containing a URL, and a misread can produce a three-digit
/// fragment; neither should become a product.
String? normaliseBarcode(String? rawValue) {
  if (rawValue == null) return null;
  final digits = rawValue.trim();
  if (!RegExp(r'^\d{8,14}$').hasMatch(digits)) return null;
  return digits;
}
