import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_routes.dart';
import '../../../auth/application/auth_controller.dart';

/// A cashier's only way to log out.
///
/// A cashier can never reach `/owner/settings` — it is owner-only, and that is where the
/// owner's own "Log out" lives — so without this, a cashier account has no logout path
/// anywhere in the app. Add to the `AppBar.actions` of every cashier-visible screen, gated
/// on [isCashierProvider] so an owner (who has their own logout in Settings) never sees a
/// duplicate.
class CashierLogoutAction extends ConsumerWidget {
  const CashierLogoutAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isCashierProvider)) return const SizedBox.shrink();
    return IconButton(
      onPressed: () => _confirmAndSignOut(context, ref),
      icon: const Icon(Icons.logout),
      tooltip: 'Log out',
    );
  }

  static Future<void> _confirmAndSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to log in again to get back to the register.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay logged in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (!context.mounted) return;
    context.go(AppRoutes.home);
  }
}
