import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/errors/app_failure.dart';
import 'core/services/firebase_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';
import 'widgets/app_logo.dart';
import 'widgets/state_views.dart';

/// The root widget.
///
/// Firebase is started here rather than in `main`, so that a startup failure renders a
/// screen with a Retry button instead of a dead app. A shop with a weak signal at opening
/// time should see "check your connection", not a white rectangle.
class ELIstaApp extends ConsumerStatefulWidget {
  const ELIstaApp({super.key});

  @override
  ConsumerState<ELIstaApp> createState() => _ELIstaAppState();
}

class _ELIstaAppState extends ConsumerState<ELIstaApp> {
  late Future<BootstrapResult> _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = FirebaseBootstrap.ensureInitialised();
  }

  void _retry() {
    setState(() {
      _bootstrap = FirebaseBootstrap.ensureInitialised();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BootstrapResult>(
      future: _bootstrap,
      builder: (context, snapshot) {
        final result = snapshot.data;

        if (result is BootstrapFailure) {
          return _BootstrapShell(
            child: ErrorView(failure: result.failure, onRetry: _retry),
          );
        }

        if (result is! BootstrapSuccess) {
          return const _BootstrapShell(child: LoadingView());
        }

        return const _RoutedApp();
      },
    );
  }
}

/// A minimal MaterialApp used only before the router exists.
///
/// It carries the real theme so the startup and failure screens do not flash a different
/// set of colours before the app proper appears.
class _BootstrapShell extends StatelessWidget {
  const _BootstrapShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Lista',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 88),
                    const SizedBox(height: 28),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutedApp extends ConsumerWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'E-Lista',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) {
        final app = child ?? const SizedBox.shrink();
        // A store owner running against emulators must never mistake demo data for their
        // real till, so the build says so, permanently and unmissably.
        return AppConfig.isDevelopmentBackend
            ? Banner(
                message: 'EMULATOR',
                location: BannerLocation.topEnd,
                child: app,
              )
            : app;
      },
    );
  }
}

/// A failure raised before the app has a screen to show it on.
///
/// Kept here so `main` has something typed to hand to the error widget.
AppFailure startupFailure(Object error, StackTrace stackTrace) {
  return AppFailure(
    message: 'E-Lista could not start. Please reopen the app.',
    code: 'startup',
    cause: error,
    stackTrace: stackTrace,
  );
}
