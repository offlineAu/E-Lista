import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// The Firebase SDK singletons, exposed as providers.
///
/// Nothing outside this file reaches for `FirebaseFirestore.instance` directly. Going
/// through a provider means a test can override the instance — or the repository built on
/// top of it — without the production code knowing anything about tests.
///
/// These throw if read before `FirebaseBootstrap.ensureInitialised()` has completed, which
/// is deliberate: it turns "used Firebase too early" into an immediate, obvious failure
/// during development rather than a confusing one in the field.

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion);
});

final firebaseStorageProvider = Provider<FirebaseStorage>((ref) {
  return FirebaseStorage.instance;
});
