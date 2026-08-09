import 'package:e_lista/core/errors/app_failure.dart';
import 'package:e_lista/features/auth/application/auth_controller.dart';
import 'package:e_lista/models/user_profile.dart';
import 'package:e_lista/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the controller asked for, without any Firebase.
///
/// The point of these tests is one decision: a guest who creates an account must be
/// *linked* to it, keeping their uid — and therefore their cart at `carts/{uid}` and every
/// order with `customerId == uid`. Registering them afresh would silently orphan both, and
/// it is exactly the kind of thing that looks fine in a demo where the guest had an empty
/// basket.
class FakeAuthService implements AuthService {
  FakeAuthService({this.isSignedIn = false, this.isAnonymous = false});

  bool isSignedIn;
  bool isAnonymous;

  final List<String> calls = [];
  Object? failWith;

  @override
  User? get currentUser => isSignedIn ? _StubUser(isAnonymous) : null;

  @override
  String? get currentUid => isSignedIn ? 'uid-1' : null;

  @override
  Stream<User?> userChanges() => const Stream.empty();

  @override
  Future<void> signInAsGuest() async => _record('signInAsGuest');

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async => _record('signInWithEmail');

  @override
  Future<void> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async => _record('registerWithEmail');

  @override
  Future<void> linkGuestToEmail({
    required String email,
    required String password,
    String? displayName,
  }) async => _record('linkGuestToEmail');

  @override
  Future<void> signOut() async => _record('signOut');

  @override
  Future<void> sendPasswordReset(String email) async =>
      _record('sendPasswordReset');

  @override
  Future<UserRole> resolveRole(User user, {bool forceRefresh = false}) async {
    _record('resolveRole');
    return isAnonymous ? UserRole.guest : UserRole.customer;
  }

  @override
  Future<void> refresh() async => _record('refresh');

  void _record(String call) {
    calls.add(call);
    final failure = failWith;
    if (failure != null) throw failure;
  }
}

/// Enough of a [User] for the controller, which only reads `isAnonymous`.
class _StubUser implements User {
  _StubUser(this._isAnonymous);

  final bool _isAnonymous;

  @override
  bool get isAnonymous => _isAnonymous;

  @override
  String get uid => 'uid-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthController controllerWith(FakeAuthService service) {
  return AuthController(service);
}

void main() {
  group('starting up', () {
    test('signs in anonymously when nobody is signed in', () async {
      final service = FakeAuthService();
      await controllerWith(service).ensureSignedIn();

      expect(service.calls, ['signInAsGuest']);
    });

    test('does nothing when a session already exists', () async {
      final service = FakeAuthService(isSignedIn: true, isAnonymous: true);
      await controllerWith(service).ensureSignedIn();

      expect(
        service.calls,
        isEmpty,
        reason: 'reopening the app must not start a second guest session',
      );
    });
  });

  group('creating an account', () {
    test('links a guest, keeping their uid, cart and orders', () async {
      final service = FakeAuthService(isSignedIn: true, isAnonymous: true);

      await controllerWith(service).register(
        email: 'ana@example.com',
        password: 'password123',
        displayName: 'Ana',
      );

      expect(service.calls, ['linkGuestToEmail']);
      expect(
        service.calls,
        isNot(contains('registerWithEmail')),
        reason: 'registering afresh would orphan the guest’s cart and orders',
      );
    });

    test('registers normally when there is no guest session to keep', () async {
      final service = FakeAuthService();

      await controllerWith(
        service,
      ).register(email: 'ana@example.com', password: 'password123');

      expect(service.calls, ['registerWithEmail']);
    });

    test('registers normally for an already-permanent account', () async {
      final service = FakeAuthService(isSignedIn: true);

      await controllerWith(
        service,
      ).register(email: 'second@example.com', password: 'password123');

      expect(service.calls, ['registerWithEmail']);
    });
  });

  group('state', () {
    test('reports success as data, not as an error', () async {
      final controller = controllerWith(FakeAuthService());
      await controller.signIn(email: 'a@b.com', password: 'password123');

      expect(controller.state.hasError, isFalse);
      expect(controller.state.isLoading, isFalse);
    });

    test('surfaces a failure without throwing at the call site', () async {
      final service = FakeAuthService()
        ..failWith = const AppFailure.invalidInput(
          'Email or password is wrong.',
        );
      final controller = controllerWith(service);

      await controller.signIn(email: 'a@b.com', password: 'nope');

      expect(controller.state.hasError, isTrue);
      expect(
        (controller.state.error! as AppFailure).message,
        'Email or password is wrong.',
      );
    });

    test('clearing the error lets a form be retried cleanly', () async {
      final service = FakeAuthService()..failWith = const AppFailure.notFound();
      final controller = controllerWith(service);

      await controller.signIn(email: 'a@b.com', password: 'nope');
      expect(controller.state.hasError, isTrue);

      controller.clearError();
      expect(controller.state.hasError, isFalse);
    });

    test(
      'signing out drops back to a guest session, not to a login wall',
      () async {
        final service = FakeAuthService(isSignedIn: true);
        await controllerWith(service).signOut();

        expect(service.calls, ['signOut']);
      },
    );
  });

  group('providers', () {
    test('the session providers read from the current session', () {
      final container = ProviderContainer(
        overrides: [
          currentSessionProvider.overrideWithValue(
            const AuthSession(
              uid: 'uid-1',
              role: UserRole.owner,
              isAnonymous: false,
              profile: UserProfile(
                uid: 'uid-1',
                role: UserRole.owner,
                isAnonymous: false,
                displayName: 'Nanay Cora',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isOwnerProvider), isTrue);
      expect(container.read(isGuestProvider), isFalse);
      expect(container.read(currentUidProvider), 'uid-1');
    });

    test('a guest session is a customer, not an owner', () {
      final container = ProviderContainer(
        overrides: [
          currentSessionProvider.overrideWithValue(
            const AuthSession(
              uid: 'uid-2',
              role: UserRole.guest,
              isAnonymous: true,
              profile: UserProfile(
                uid: 'uid-2',
                role: UserRole.guest,
                isAnonymous: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isOwnerProvider), isFalse);
      expect(container.read(isGuestProvider), isTrue);
    });

    test('no session yet is neither owner nor guest', () {
      final container = ProviderContainer(
        overrides: [currentSessionProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      expect(container.read(isOwnerProvider), isFalse);
      expect(container.read(currentUidProvider), isNull);
    });
  });

  group('roles', () {
    test('a guest counts as a customer, never as an owner', () {
      expect(UserRole.guest.isCustomer, isTrue);
      expect(UserRole.guest.isOwner, isFalse);
      expect(UserRole.customer.isCustomer, isTrue);
      expect(UserRole.owner.isOwner, isTrue);
      expect(UserRole.owner.isCustomer, isFalse);
    });

    test('an unknown stored role reads as customer, never as owner', () {
      expect(UserRole.fromJson('superuser'), UserRole.customer);
      expect(UserRole.fromJson(null), UserRole.customer);
      expect(UserRole.fromJson(''), UserRole.customer);
    });

    test('a guest profile can still be upgraded', () {
      const guest = UserProfile(
        uid: 'uid-1',
        role: UserRole.guest,
        isAnonymous: true,
      );
      expect(guest.canBecomePermanent, isTrue);

      const registered = UserProfile(
        uid: 'uid-1',
        role: UserRole.customer,
        isAnonymous: false,
      );
      expect(registered.canBecomePermanent, isFalse);
    });

    test('checkout knows when it still has to ask for details', () {
      const bare = UserProfile(
        uid: 'uid-1',
        role: UserRole.guest,
        isAnonymous: true,
      );
      expect(bare.hasContactDetails, isFalse);

      const complete = UserProfile(
        uid: 'uid-1',
        role: UserRole.customer,
        isAnonymous: false,
        displayName: 'Ana',
        phoneNumber: '09171234567',
      );
      expect(complete.hasContactDetails, isTrue);
    });
  });
}
