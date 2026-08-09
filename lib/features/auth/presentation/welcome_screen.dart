import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../widgets/app_logo.dart';
import '../../../widgets/state_views.dart';
import '../application/auth_controller.dart';

/// The three ways into the app: keep shopping as a guest, log in, or create an account.
///
/// Guest is the primary action and it is first, because requiring registration to see what
/// a neighbourhood store sells is the fastest way to lose a customer. Logging in is for
/// people who already have an account — including the owner.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.watch(authControllerProvider);
    final isBusy = controller.isLoading;

    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        showFailureSnackBar(context, next.error!);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const Center(child: AppLogo(size: 104)),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to E-Lista',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Browse the shelves, add to your cart and order — '
                    'no account needed.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 36),
                  FilledButton(
                    onPressed: isBusy
                        ? null
                        : () async {
                            await ref
                                .read(authControllerProvider.notifier)
                                .continueAsGuest();
                            if (context.mounted &&
                                !ref.read(authControllerProvider).hasError) {
                              context.go(AppRoutes.home);
                            }
                          },
                    child: isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Continue as guest'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: isBusy
                        ? null
                        : () => context.push(AppRoutes.login),
                    child: const Text('Log in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isBusy
                        ? null
                        : () => context.push(AppRoutes.register),
                    child: const Text('Create an account'),
                  ),
                  const SizedBox(height: 28),
                  _GuestNote(theme: theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuestNote extends StatelessWidget {
  const _GuestNote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Shopping as a guest keeps your cart on this device. '
                'You can create an account later and your cart and orders come with you.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
