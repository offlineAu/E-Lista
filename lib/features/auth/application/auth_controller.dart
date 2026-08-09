import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../../models/user_profile.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/auth_service.dart';

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
    yield await _buildSession(auth, users, user);
  }
});

Future<AuthSession> _buildSession(
  AuthService auth,
  UserRepository users,
  User user,
) async {
  // The claim is the authority; the document is a mirror the UI reads.
  final role = await auth.resolveRole(user);
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
        await _auth.linkGuestToEmail(
          email: email,
          password: password,
          displayName: displayName,
        );
      } else {
        await _auth.registerWithEmail(
          email: email,
          password: password,
          displayName: displayName,
        );
      }
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
