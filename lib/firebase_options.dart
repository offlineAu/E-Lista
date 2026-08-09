// Firebase configuration for E-Lista.
//
// THIS FILE IS A PLACEHOLDER AND IS NOT CONNECTED TO A REAL FIREBASE PROJECT.
//
// No Firebase project exists for this app yet. Rather than ship invented API keys that
// would fail at runtime with an unhelpful error, this file does two honest things:
//
//   * With `--dart-define=USE_FIREBASE_EMULATOR=true` it returns options for the reserved
//     `demo-e-lista` project id. The Firebase Emulator Suite accepts any project id
//     beginning with `demo-` without contacting Google, so the whole app — auth, Firestore,
//     Functions, Storage — runs locally against real Firebase SDKs.
//   * Without that flag it throws an error naming the exact command to run.
//
// To connect a real project, replace this file by running:
//
//     dart pub global activate flutterfire_cli
//     flutterfire configure --project <your-project-id>
//
// That regenerates this file with real values and writes the platform config files
// (android/app/google-services.json, ios/Runner/GoogleService-Info.plist). Nothing else in
// the app changes: `Firebase.initializeApp` is called in exactly one place.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'core/config/app_config.dart';

/// Raised when the app is started against a real backend but no Firebase project has been
/// configured. The message is aimed at whoever is building the app, not at a shopper.
class FirebaseNotConfiguredError extends Error {
  FirebaseNotConfiguredError(this.platform);

  final String platform;

  @override
  String toString() =>
      '''
Firebase is not configured for $platform.

E-Lista has no Firebase project yet. Either:

  1. Run the app against the local emulator suite:
       firebase emulators:start
       flutter run --dart-define=USE_FIREBASE_EMULATOR=true

  2. Or connect a real project, which regenerates lib/firebase_options.dart:
       dart pub global activate flutterfire_cli
       flutterfire configure --project <your-project-id>
''';
}

/// The Firebase options for the platform the app is running on.
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (AppConfig.useFirebaseEmulator) return _demoProject;

    if (kIsWeb) throw FirebaseNotConfiguredError('web');
    throw FirebaseNotConfiguredError(defaultTargetPlatform.name);
  }

  /// Options for a `demo-` project, which the emulator suite serves entirely locally.
  ///
  /// The values below are not credentials. The emulators never validate them, and a
  /// `demo-` project id cannot reach Google's servers even by accident — which is the
  /// property that makes local development safe.
  static const FirebaseOptions _demoProject = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-e-lista',
    storageBucket: 'demo-e-lista.appspot.com',
    authDomain: 'demo-e-lista.firebaseapp.com',
  );

  /// True when the build has real project configuration compiled in.
  ///
  /// The app shows a development banner while this is false so a demo is never mistaken
  /// for a live store.
  static bool get isConfigured => !AppConfig.useFirebaseEmulator;

  /// Name of the platform, for diagnostics.
  static String get platformLabel =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Whether the current platform is one the app ships on.
  static bool get isSupportedPlatform =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
