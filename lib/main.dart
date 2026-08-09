import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/theme/app_colors.dart';

/// Entry point.
///
/// Two things happen before `runApp`, and nothing else: error handling is installed, and
/// the Flutter binding is initialised. Firebase is started inside the app widget instead,
/// so that a failure there produces a screen with a Retry button rather than a crash
/// before anything has been drawn.
void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      _installErrorHandlers();
      runApp(const ProviderScope(child: ELIstaApp()));
    },
    (error, stackTrace) {
      // Anything that escaped every guard. Logged rather than swallowed: a silent failure
      // is the one thing this app's error handling is meant to prevent.
      developer.log(
        'Uncaught error',
        name: 'e_lista',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

void _installErrorHandlers() {
  // In release, a red error box in the middle of a shop's checkout screen helps nobody.
  // Replace it with something calm that says what to do.
  ErrorWidget.builder = (details) {
    if (kDebugMode) return ErrorWidget(details.exception);
    return const _CalmErrorWidget();
  };

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'Flutter framework error',
      name: 'e_lista',
      level: 1000,
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    developer.log(
      'Platform error',
      name: 'e_lista',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
}

/// What a customer sees if a widget throws in release: an explanation, not a stack trace.
class _CalmErrorWidget extends StatelessWidget {
  const _CalmErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.cream,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.danger, size: 40),
              SizedBox(height: 12),
              Text(
                'Something on this screen could not be shown.\n'
                'Please go back and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.charcoal, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
