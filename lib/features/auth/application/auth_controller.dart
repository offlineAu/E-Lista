import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, User;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../models/user_profile.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/auth_service.dart';

/// Auth error codes meaning the remembered guest session itself is gone — not that the new
/// email or password is wrong. A device can hold onto a guest sign-in whose account the
/// backend no longer recognises (wiped local emulator data, an expired or pruned anonymous
/// account); linking to it fails for a reason the person creating an account had no part in
/// and cannot fix by retyping anything.
const _staleGuestSessionCodes = {
  'user-token-expired',
  'invalid-user-token',
  'user-not-found',
};

/// Identity Toolkit's own error codes for a dead refresh token. The Android SDK often
/// cannot classify these into one of its own [FirebaseAuthException] codes, so it reports
/// the whole thing as `unknown` and leaves the real reason sitting inside the message
/// instead — this is what that looks like when it happens.
const _staleGuestSessionMessages = ['INVALID_REFRESH_TOKEN', 'TOKEN_EXPIRED'];

bool _isStaleGuestSession(AppFailure failure) {
  if (_staleGuestSessionCodes.contains(failure.code)) return true;
  final cause = failure.cause;
  if (cause is! FirebaseAuthException) return false;
  final message = cause.message;
  if (message == null) return false;
  return _staleGuestSessionMessages.any(message.contains);
}

final authServiceProvider = Provider<AuthService>((ref) {
  return FirebaseAuthService(ref.watch(firebaseAuthProvider));
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(firestoreProvider));
});

/// Who is using the app right now.
///
/// There is always a session once the app has started: a shopper who has not signed in is
/// signed in *anonymously*, which is what lets guests have carts and orders like anyone
/// else. `null` means the app is still starting up, not that nobody is there.
@immutable
class AuthSession {
  const AuthSession({
    required this.uid,
    required this.role,
    required this.profile,
    required this.isAnonymous,
  });

  final String uid;

  /// The role from the ID token's custom claim — the same value Firestore rules enforce.
  final UserRole role;

  /// The profile document, kept in step with Firebase Auth on every sign-in.
  final UserProfile profile;

  final bool isAnonymous;

  bool get isOwner => role.isOwner;

  bool get isCashier => role.isCashier;

  /// True for both guests and registered shoppers.
  bool get isCustomer => role.isCustomer;

  /// True while the account can still be upgraded by linking an email.
  bool get isGuest => isAnonymous;

  /// What to call this person in the UI.
  String get greetingName => isAnonymous ? 'there' : profile.greetingName;

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.uid == uid &&
      other.role == role &&
      other.isAnonymous == isAnonymous &&
      other.profile == profile;

  @override
  int get hashCode => Object.hash(uid, role, isAnonymous, profile);

  @override
  String toString() => 'AuthSession($uid, ${role.name}, guest: $isAnonymous)';
}

/// The live session, rebuilt whenever Firebase Auth reports a change.
///
/// Listening to `userChanges` rather than `authStateChanges` matters here: linking a guest
/// to an email keeps the same uid, so only `userChanges` fires. Without it the app would
/// still be calling a newly registered customer a guest.
final authSessionProvider = StreamProvider<AuthSession?>((ref) async* {
  final auth = ref.watch(authServiceProvider);
  final users = ref.watch(userRepositoryProvider);

  await for (final user in auth.userChanges()) {
    if (user == null) {
      yield null;
      continue;
    }
    try {
      yield await _buildSessionWithRetry(auth, users, user);
    } catch (error) {
      // However generous the retry budget below, treat it as not necessarily enough:
      // a session that still fails to build must not end this stream for the rest of the
      // app run — no future sign-in would ever get a chance to rebuild it, which is a far
      // worse outcome than silently keeping whatever session already existed and letting
      // the next auth change (or a manual retry) try again.
      debugPrint(
        'e_lista: giving up building the session for ${user.uid} — cause=$error',
      );
    }
  }
});

/// Retry delays for a transient permission-denied right after a sign-in/sign-out swap.
///
/// Firestore's client can treat requests as entirely unauthenticated for a brief window
/// right after Firebase Auth swaps the signed-in user — not a wrong role, but no credential
/// attached yet at all — so even reading your own document can be refused for a moment. On
/// the local emulator this window is imperceptible; over a real network to a real project it
/// can run past a second, which is why this budget is generous rather than merely brief. A
/// genuine permission problem (an account that actually lacks access) still surfaces once
/// these run out.
const _staleCredentialRetryDelays = [
  Duration(milliseconds: 400),
  Duration(milliseconds: 800),
  Duration(milliseconds: 1500),
  Duration(seconds: 3),
  Duration(seconds: 5),
];

Future<AuthSession> _buildSessionWithRetry(
  AuthService auth,
  UserRepository users,
  User user,
) async {
  for (final delay in _staleCredentialRetryDelays) {
    try {
      return await _buildSession(auth, users, user);
    } on AppFailure catch (failure) {
      if (failure.code != 'permission-denied') rethrow;
      await Future<void>.delayed(delay);
    }
  }
  return _buildSession(auth, users, user);
}

Future<AuthSession> _buildSession(
  AuthService auth,
  UserRepository users,
  User user,
) async {
  // The claim is the authority; the document is a mirror the UI reads. A cached ID token
  // can be up to an hour stale, so a role change made moments ago — granting or revoking
  // ownership — would otherwise not show up until that cache happened to expire on its
  // own. Forcing a refresh here, on every session rebuild, is what makes "you are now the
  // owner" true the moment it is said rather than eventually.
  final role = await auth.resolveRole(user, forceRefresh: true);
  debugPrint('e_lista: resolved role for ${user.uid} = $role');
  final profile = await users.ensureProfile(user, knownRole: role);
  return AuthSession(
    uid: user.uid,
    role: role,
    profile: profile,
    isAnonymous: user.isAnonymous,
  );
}

/// The current session, or `null` while starting up.
///
/// Convenience for widgets that only need the value and treat loading and error alike.
final currentSessionProvider = Provider<AuthSession?>((ref) {
  return ref.watch(authSessionProvider).valueOrNull;
});

/// Whether the current user is the store owner.
///
/// Used to choose which shell to show. It is *not* what protects owner data — Firestore
/// rules do that, and they read the same claim rather than trusting this.
final isOwnerProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider)?.isOwner ?? false;
});

/// Whether the current user is a cashier — staff, but restricted: can process orders and
/// record stock movements, not prices, costs, settings or other staff. Same caveat as
/// [isOwnerProvider]: this is a UI convenience, not the security boundary.
final isCashierProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider)?.isCashier ?? false;
});

/// Whether the current user is browsing as a guest.
final isGuestProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider)?.isGuest ?? false;
});

/// The current uid, or `null` before sign-in completes.
final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(currentSessionProvider)?.uid;
});

/// Actions that change who is signed in.
///
/// Screens call these and watch [state] for progress; the session itself updates through
/// [authSessionProvider], so no screen has to thread a user object around.
class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._auth) : super(const AsyncValue.data(null));

  final AuthService _auth;

  /// Signs in anonymously if nobody is signed in yet.
  ///
  /// Idempotent, and called on every start: this is what makes the app usable before any
  /// decision about accounts has been made.
  Future<void> ensureSignedIn() async {
    if (_auth.currentUser != null) return;
    await _run(_auth.signInAsGuest);
  }

  Future<void> continueAsGuest() => _run(_auth.signInAsGuest);

  Future<void> signIn({required String email, required String password}) {
    return _run(() => _auth.signInWithEmail(email: email, password: password));
  }

  /// Creates an account.
  ///
  /// A guest is *upgraded* rather than replaced, so their cart and order history follow
  /// them. Someone who is not a guest gets a fresh account.
  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) {
    final user = _auth.currentUser;
    final shouldLink = user != null && user.isAnonymous;

    return _run(() async {
      if (shouldLink) {
        try {
          await _auth.linkGuestToEmail(
            email: email,
            password: password,
            displayName: displayName,
          );
          return;
        } on AppFailure catch (failure) {
          if (!_isStaleGuestSession(failure)) rethrow;
          // The remembered guest never existed on the backend — nothing to keep. Register
          // fresh instead of surfacing a failure the person can do nothing about.
        }
      }
      await _auth.registerWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );
    });
  }

  Future<void> signOut() => _run(_auth.signOut);

  Future<void> sendPasswordReset(String email) {
    return _run(() => _auth.sendPasswordReset(email));
  }

  /// Clears an error so a form can be retried without the old message lingering.
  void clearError() {
    if (state.hasError) state = const AsyncValue.data(null);
  }

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncValue.loading();
    try {
      await action();
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      // Already an AppFailure: AuthService translates everything it throws.
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
      return AuthController(ref.watch(authServiceProvider));
    });
