import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/utils/validators.dart';
import '../services/barcode_scanner_service.dart';
import 'text_prompt_dialog.dart';

final barcodeScannerServiceProvider = Provider<BarcodeScannerService>((ref) {
  return const MobileBarcodeScannerService();
});

/// A camera viewfinder that reports each accepted barcode exactly once.
///
/// Two behaviours matter for real use at a shelf:
///
/// * **Debouncing.** A camera reports the same barcode many times a second. Without a
///   cooldown, one pack scanned once would add stock a dozen times.
/// * **A manual fallback.** Cameras fail, packs get scuffed, and the web build has no
///   scanner at all. Typing the number is always available, never a hidden last resort.
class BarcodeScannerView extends ConsumerStatefulWidget {
  const BarcodeScannerView({
    required this.onBarcode,
    super.key,
    this.isPaused = false,
    this.hint,
  });

  /// Called once per accepted scan, after the cooldown.
  final ValueChanged<String> onBarcode;

  /// Stops accepting scans — used while a sheet is open over the viewfinder.
  final bool isPaused;

  /// A line under the viewfinder telling the user what this scan will do.
  final String? hint;

  @override
  ConsumerState<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends ConsumerState<BarcodeScannerView> {
  MobileScannerController? _controller;
  String? _lastAccepted;
  DateTime? _lastAcceptedAt;

  /// How long the same barcode is ignored after being accepted.
  ///
  /// Long enough that holding a pack still under the camera does not double-count it,
  /// short enough that deliberately scanning the same product twice in a restock run
  /// works.
  static const Duration _cooldown = Duration(milliseconds: 1800);

  @override
  void initState() {
    super.initState();
    final service = ref.read(barcodeScannerServiceProvider);
    _controller = service.createController() as MobileScannerController?;
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (widget.isPaused) return;

    final service = ref.read(barcodeScannerServiceProvider);
    for (final barcode in capture.barcodes) {
      final value = service.normalise(barcode.rawValue);
      if (value == null) continue;

      final now = DateTime.now();
      final isRepeat =
          value == _lastAccepted &&
          _lastAcceptedAt != null &&
          now.difference(_lastAcceptedAt!) < _cooldown;
      if (isRepeat) continue;

      _lastAccepted = value;
      _lastAcceptedAt = now;
      widget.onBarcode(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;

    if (controller == null) {
      return _ManualEntryOnly(onBarcode: widget.onBarcode, hint: widget.hint);
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _ScannerError(
                  message: _describeScannerError(error),
                  onManualEntry: () => _promptForBarcode(context),
                ),
              ),
              const _ViewfinderFrame(),
              if (widget.isPaused)
                ColoredBox(
                  color: theme.colorScheme.scrim.withValues(alpha: 0.6),
                  child: const Center(
                    child: Text(
                      'Scanning paused',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Column(
            children: [
              if (widget.hint != null)
                Text(
                  widget.hint!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: controller.toggleTorch,
                    icon: const Icon(Icons.flashlight_on_outlined),
                    label: const Text('Torch'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _promptForBarcode(context),
                    icon: const Icon(Icons.keyboard_outlined),
                    label: const Text('Type the number'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _promptForBarcode(BuildContext context) async {
    final barcode = await promptForBarcode(context);
    if (barcode != null) widget.onBarcode(barcode);
  }
}

/// Asks for a barcode by keyboard. Used when the camera is unavailable, unreadable, or
/// simply slower than typing.
Future<String?> promptForBarcode(BuildContext context) {
  return showTextPrompt(
    context,
    title: 'Enter the barcode',
    label: 'Barcode',
    helperText: 'The 8 to 14 digits printed under the bars.',
    keyboardType: TextInputType.number,
    confirmLabel: 'Use it',
    validator: (String? value) => Validators.barcode(value, isRequired: true),
  );
}

class _ManualEntryOnly extends StatelessWidget {
  const _ManualEntryOnly({required this.onBarcode, this.hint});

  final ValueChanged<String> onBarcode;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.no_photography_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No camera scanner here',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This device cannot scan barcodes. '
              '${hint ?? 'You can type the number instead.'}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                final barcode = await promptForBarcode(context);
                if (barcode != null) onBarcode(barcode);
              },
              icon: const Icon(Icons.keyboard_outlined),
              label: const Text('Enter a barcode'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message, required this.onManualEntry});

  final String message;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, size: 40),
              const SizedBox(height: 14),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onManualEntry,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Type the number'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bracket overlay that tells someone where to hold the pack.
class _ViewfinderFrame extends StatelessWidget {
  const _ViewfinderFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.78,
          heightFactor: 0.34,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

String _describeScannerError(MobileScannerException error) {
  return switch (error.errorCode) {
    MobileScannerErrorCode.permissionDenied =>
      'E-Lista needs camera permission to scan barcodes. '
          'Allow it in Settings, or type the number instead.',
    MobileScannerErrorCode.unsupported =>
      'This device cannot scan barcodes. You can type the number instead.',
    _ => 'The camera could not start. You can type the number instead.',
  };
}
