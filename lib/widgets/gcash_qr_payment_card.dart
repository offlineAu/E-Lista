import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/money/money.dart';
import '../core/providers/repository_providers.dart';

/// The store's GCash QR code, shown at checkout so a shopper (or a walk-in customer at the
/// register) can scan and pay directly, same as a scan-to-pay counter.
///
/// A static image, not a generated one: it just displays whatever the owner uploaded in
/// Settings. Renders nothing if no QR code has been uploaded yet, so checkout still works
/// exactly as it did before this existed.
class GcashQrPaymentCard extends ConsumerWidget {
  const GcashQrPaymentCard({required this.amount, super.key});

  final Money amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qr = ref.watch(gcashQrProvider).valueOrNull;
    if (qr == null || !qr.hasImage) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Scan to pay with GCash', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: qr.imageUrl!,
                width: 220,
                height: 220,
                fit: BoxFit.contain,
                placeholder: (context, url) => const SizedBox(
                  width: 220,
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => SizedBox(
                  width: 220,
                  height: 220,
                  child: Icon(
                    Icons.qr_code_2,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Send exactly ${amount.format()}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The store confirms the payment on their end.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
