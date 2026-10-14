import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../config/app_config.dart';
import '../errors/app_failure.dart';

/// The result of starting Firebase up.
///
/// Startup is allowed to fail without taking the app down: the shell renders, shows what
/// went wrong in plain language, and offers Retry. A store whose phone briefly has no
/// signal should see "we could not reach the store" rather than a blank screen.
sealed class BootstrapResult {
  const BootstrapResult();
}

/// Firebase is up and every service is pointed at the right backend.
class BootstrapSuccess extends BootstrapResult {
  const BootstrapSuccess({required this.usingEmulator});

  /// True when the app is talking to the local emulator suite rather than a real project.
  final bool usingEmulator;
}

/// Firebase could not be started.
class BootstrapFailure extends BootstrapResult {
  const BootstrapFailure(this.failure);

  final AppFailure failure;
}

/// Starts Firebase exactly once and wires the SDKs to the configured backend.
///
/// Everything environment-specific lives here: whether to use emulators, what offline
/// behaviour Firestore has, and how long a callable may run. No other file calls
/// `Firebase.initializeApp`, so swapping in a real project is a one-file change.
abstract final class FirebaseBootstrap {
  static bool _initialised = false;

  /// True once [ensureInitialised] has completed successfully.
  static bool get isInitialised => _initialised;

  /// Initialises Firebase, or returns a [BootstrapFailure] describing why it could not.
  ///
  /// Calling this twice is safe; the second call returns immediately.
  static Future<BootstrapResult> ensureInitialised() async {
    if (_initialised) {
      return BootstrapSuccess(usingEmulator: AppConfig.useFirebaseEmulator);
    }

    try {
      // `_initialised` alone does not survive a hot restart: that wipes Dart's isolate
      // state but leaves the native side's Firebase app registered from before the
      // restart, so calling initializeApp() again throws `core/duplicate-app`.
      // `Firebase.apps` reflects the native registry directly, so checking it first
      // makes this call idempotent across a hot restart, not just within one Dart run.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      if (AppConfig.useFirebaseEmulator) {
        await _connectEmulators();
      }

      _configureFirestore();

      _initialised = true;
      return BootstrapSuccess(usingEmulator: AppConfig.useFirebaseEmulator);
    } catch (error, stackTrace) {
      // Unlike ErrorMapper.guard, nothing has logged this yet — this is the one failure
      // that happens before any of that machinery exists.
      debugPrint('e_lista: failed to start Firebase — cause=$error');
      return BootstrapFailure(
        AppFailure(
          message:
              'We could not start the app. '
              'Check your connection and try again.',
          severity: FailureSeverity.transient,
          code: 'bootstrap-failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static Future<void> _connectEmulators() async {
    final host = AppConfig.emulatorHost;

    // Auth must be pointed at the emulator before any sign-in call is made.
    await FirebaseAuth.instance.useAuthEmulator(
      host,
      AppConfig.authEmulatorPort,
    );

    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      AppConfig.firestoreEmulatorPort,
    );

    FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
        .useFunctionsEmulator(
          host,
          AppConfig.functionsEmulatorPort,
        );

    await FirebaseStorage.instance.useStorageEmulator(
      host,
      AppConfig.storageEmulatorPort,
    );

    debugPrint(
      'E-Lista is using the Firebase emulator suite at $host. '
      'Data here is local and disposable.',
    );
  }

  static void _configureFirestore() {
    // Local persistence is what makes the catalog readable on a weak signal: products
    // already seen render from cache while the network call is still in flight.
    //
    // It is safe for reads. It is *not* what makes writes safe — orders, stock and prices
    // all go through callable functions, which fail loudly when offline rather than
    // queueing a write that would be applied against stale stock.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  /// A callable bound to the app's timeout.
  ///
  /// Every callable goes through here so none of them can be created with the SDK's
  /// 60-second default: a shopkeeper waiting on a scanner will not wait a minute, and a
  /// call that overruns should surface as a retryable timeout instead.
  static HttpsCallable callable(String name, {Duration? timeout}) {
    return FirebaseFunctions.instanceFor(
      region: AppConfig.functionsRegion,
    ).httpsCallable(
      name,
      options: HttpsCallableOptions(
        timeout: timeout ?? AppConfig.backendTimeout,
      ),
    );
  }

  /// Resets the initialised flag. Tests only.
  @visibleForTesting
  static void resetForTesting() {
    _initialised = false;
  }
}
