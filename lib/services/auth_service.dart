import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../core/errors/app_failure.dart';
import '../core/errors/error_mapper.dart';
import '../models/user_profile.dart';

/// Signing in, signing out, and turning a guest into a permanent account.
///
/// Two things about this app's account model shape everything here:
///
/// * **Every user is signed in, including guests.** "Continue as guest" performs an
///   anonymous sign-in, so a guest has a real uid and their cart and orders are ordinary
///   documents owned by that uid. Nothing has to special-case "no user".
/// * **Roles come from custom claims, not from a document.** `users/{uid}.role` is a
///   mirror the UI reads for convenience; the claim on the ID token is what Firestore
///   rules check. A client cannot mint a claim, which is what makes owner-only data
///   owner-only.
///
/// This is an interface so the sign-in flows can be tested without Firebase — in
/// particular, the rule that a guest who registers is *linked* rather than replaced, which
/// is the difference between keeping their cart and losing it.
abstract interface class AuthService {
  User? get currentUser;
  String? get currentUid;

  Stream<User?> userChanges();

  Future<void> signInAsGuest();

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> linkGuestToEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);

  Future<UserRole> resolveRole(User user, {bool forceRefresh});

  Future<void> refresh();
}

/// [AuthService] backed by Firebase Authentication.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;

  /// The signed-in Firebase user, or `null` before the first sign-in completes.
  @override
  User? get currentUser => _auth.currentUser;

  @override
  String? get currentUid => _auth.currentUser?.uid;

  /// Emits on sign-in, sign-out and token refresh.
  ///
  /// `userChanges` rather than `authStateChanges`: linking a guest to an email keeps the
  /// same uid, so `authStateChanges` would not fire and the UI would keep calling them a
  /// guest after they created an account.
  @override
  Stream<User?> userChanges() => _auth.userChanges();

  /// Signs in anonymously so a shopper can browse and buy without an account.
  ///
  /// This is the app's default entry point, not a fallback: requiring registration to see
  /// what a sari-sari store sells would be the wrong trade.
  @override
  Future<User> signInAsGuest() async {
    return ErrorMapper.guard(() async {
      final existing = _auth.currentUser;
      if (existing != null) return existing;
      final credential = await _auth.signInAnonymously();
      return _requireUser(credential.user);
    }, operation: 'start as a guest');
  }

  /// Signs in with email and password.
  @override
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) {
    return ErrorMapper.guard(() async {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _requireUser(credential.user);
    }, operation: 'sign you in');
  }

  /// Creates a brand-new account.
  ///
  /// Used when someone chooses "Create account" from the welcome screen without having
  /// browsed first. A guest who already has a cart goes through [linkGuestToEmail]
  /// instead, which keeps their uid and therefore their cart and orders.
  @override
  Future<User> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) {
    return ErrorMapper.guard(() async {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = _requireUser(credential.user);
      final name = displayName?.trim();
      if (name != null && name.isNotEmpty) {
        await user.updateDisplayName(name);
        await user.reload();
      }
      return _requireUser(_auth.currentUser ?? user);
    }, operation: 'create your account');
  }

  /// Upgrades the current anonymous account into a permanent one.
  ///
  /// The uid does not change, which is the entire point: the guest's cart at
  /// `carts/{uid}` and every order they placed at `orders/*` with `customerId == uid`
  /// keep belonging to them. Nothing is copied, so nothing can be lost in the copying.
  @override
  Future<User> linkGuestToEmail({
    required String email,
    required String password,
    String? displayName,
  }) {
    return ErrorMapper.guard(() async {
      final user = _auth.currentUser;
      if (user == null) {
        throw const AppFailure(
          message: 'Start shopping first, then create your account to keep it.',
          severity: FailureSeverity.userCorrectable,
          code: 'no-current-user',
        );
      }
      if (!user.isAnonymous) {
        throw const AppFailure(
          message: 'This device already has an account signed in.',
          severity: FailureSeverity.userCorrectable,
          code: 'already-permanent',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );
      final linked = await user.linkWithCredential(credential);
      final upgraded = _requireUser(linked.user);

      final name = displayName?.trim();
      if (name != null && name.isNotEmpty) {
        await upgraded.updateDisplayName(name);
        await upgraded.reload();
      }
      return _requireUser(_auth.currentUser ?? upgraded);
    }, operation: 'create your account');
  }

  /// Signs out and immediately starts a fresh guest session.
  ///
  /// The app is never in a signed-out state: leaving an account should drop you back into
  /// browsing, not onto a login wall.
  @override
  Future<User> signOut() {
    return ErrorMapper.guard(() async {
      await _auth.signOut();
      final credential = await _auth.signInAnonymously();
      return _requireUser(credential.user);
    }, operation: 'sign you out');
  }

  /// Sends a password reset email.
  @override
  Future<void> sendPasswordReset(String email) {
    return ErrorMapper.guard(
      () => _auth.sendPasswordResetEmail(email: email.trim()),
      operation: 'send a reset email',
    );
  }

  /// The role carried by the user's ID token.
  ///
  /// [forceRefresh] fetches a new token; needed right after a role is granted, because a
  /// cached token keeps its old claims for up to an hour otherwise.
  @override
  Future<UserRole> resolveRole(User user, {bool forceRefresh = false}) {
    return ErrorMapper.guard(() async {
      if (user.isAnonymous) return UserRole.guest;
      final token = await user.getIdTokenResult(forceRefresh);
      debugPrint(
        'e_lista: raw claims for ${user.uid} (forceRefresh=$forceRefresh) = '
        '${token.claims}',
      );
      return UserRole.fromJson(token.claims?['role']);
    }, operation: 'check your account');
  }

  /// Re-reads the current user from Firebase.
  ///
  /// Called after a role change or an email verification so the UI reflects it without a
  /// restart.
  @override
  Future<void> refresh() {
    return ErrorMapper.guard(
      () async => _auth.currentUser?.reload(),
      operation: 'refresh your account',
    );
  }

  static User _requireUser(User? user) {
    if (user != null) return user;
    throw const AppFailure(
      message: 'We could not complete that sign-in. Please try again.',
      code: 'missing-user',
    );
  }
}
