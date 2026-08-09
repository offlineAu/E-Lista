import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/app_logo.dart';
import '../../../widgets/state_views.dart';
import '../application/auth_controller.dart';

/// The first screen, shown while the app works out who is using it.
///
/// It does one thing: make sure a session exists. Someone opening the app for the first
/// time is signed in anonymously here, which is what lets them go straight to the shelves
/// without a decision about accounts. The router moves them on as soon as the session
/// lands.
///
/// If sign-in fails — no signal, Firebase unreachable — this screen says so and offers
/// Retry rather than spinning forever.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the brand mark is on screen before any network work.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
  }

  Future<void> _startSession() async {
    await ref.read(authControllerProvider.notifier).ensureSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signIn = ref.watch(authControllerProvider);
    final session = ref.watch(authSessionProvider);

    final failure = signIn.error ?? session.error;
    final hasFailed = signIn.hasError || session.hasError;

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.light
          ? AppColors.cream
          : AppColors.darkBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppLogo(size: 96),
                const SizedBox(height: 20),
                Text('E-Lista', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  'Your sari-sari store, in your pocket',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                if (hasFailed && failure != null)
                  ErrorView.from(
                    failure,
                    signIn.stackTrace ?? session.stackTrace,
                    onRetry: _startSession,
                    compact: true,
                  )
                else
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
