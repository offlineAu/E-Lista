import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

import '../core/config/app_config.dart';
import '../core/errors/error_mapper.dart';
import '../models/user_profile.dart';

/// Reads and writes `users/{uid}`.
///
/// The document holds the shopper's name, phone and address so checkout does not ask for
/// them twice, plus a mirror of the role for the UI. Security rules let a user read and
/// write only their own document, and reject any write that changes `role` — the
/// authoritative role is the custom claim on the ID token, which only a Cloud Function
/// can set.
class UserRepository {
  UserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collectionPath = 'users';

  CollectionReference<Map<String, Object?>> get _users =>
      _firestore.collection(collectionPath);

  /// Streams the profile document, emitting `null` while it does not exist yet.
  Stream<UserProfile?> watch(String uid) {
    return _users.doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return UserProfile.fromJson(uid, data);
    });
  }

  Future<UserProfile?> fetch(String uid) {
    return ErrorMapper.guard(() async {
      final snapshot = await _users.doc(uid).get();
      final data = snapshot.data();
      if (data == null) return null;
      return UserProfile.fromJson(uid, data);
    }, operation: 'load your profile', timeout: AppConfig.backendTimeout);
  }

  /// Creates the profile document if it is missing, and keeps the fields Firebase Auth
  /// owns — email, display name, anonymous flag — in step with it.
  ///
  /// Called on every sign-in, including the anonymous one, so a guest has a profile from
  /// their first tap and their details survive the upgrade to a real account.
  ///
  /// The role is only ever written on create, and only ever as `customer`; an existing
  /// document's role is left exactly as it is, because the client is not allowed to change
  /// it and must not try.
  Future<UserProfile> ensureProfile(User user, {UserRole? knownRole}) {
    return ErrorMapper.guard(() async {
      final reference = _users.doc(user.uid);
      final snapshot = await reference.get();
      final existing = snapshot.data();

      if (existing == null) {
        final profile = UserProfile(
          uid: user.uid,
          // A new document is always a customer. Ownership is granted server-side.
          role: UserRole.customer,
          isAnonymous: user.isAnonymous,
          displayName: user.displayName,
          email: user.email,
          phoneNumber: user.phoneNumber,
        );
        await reference.set(profile.toJson());
        return profile.copyWith(role: knownRole ?? UserRole.customer);
      }

      final current = UserProfile.fromJson(user.uid, existing);
      final synced = current.copyWith(
        isAnonymous: user.isAnonymous,
        displayName: user.displayName ?? current.displayName,
        email: user.email ?? current.email,
        phoneNumber: user.phoneNumber ?? current.phoneNumber,
        role: knownRole ?? current.role,
      );

      // Only write when Firebase Auth actually disagrees with the document, so opening
      // the app does not cost a write every time.
      if (synced.isAnonymous != current.isAnonymous ||
          synced.displayName != current.displayName ||
          synced.email != current.email ||
          synced.phoneNumber != current.phoneNumber) {
        await reference.update({
          'isAnonymous': synced.isAnonymous,
          'displayName': synced.displayName,
          'email': synced.email,
          'phoneNumber': synced.phoneNumber,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return synced;
    }, operation: 'set up your profile', timeout: AppConfig.backendTimeout);
  }

  /// Updates the details a shopper may edit.
  ///
  /// `role` and `uid` are deliberately absent: the rules reject a write that changes
  /// either, so including them would only produce a permission error.
  Future<void> updateContactDetails(
    String uid, {
    String? displayName,
    String? phoneNumber,
    String? address,
  }) {
    return ErrorMapper.guard(() async {
      final updates = <String, Object?>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (displayName != null) updates['displayName'] = displayName.trim();
      if (phoneNumber != null) updates['phoneNumber'] = phoneNumber.trim();
      if (address != null) updates['address'] = address.trim();

      await _users.doc(uid).set(updates, SetOptions(merge: true));
    }, operation: 'save your details');
  }

  /// Records the contact details a customer typed at checkout, so the next order is
  /// prefilled.
  Future<void> rememberCheckoutDetails(
    String uid, {
    required String name,
    required String phoneNumber,
    String? address,
  }) {
    return updateContactDetails(
      uid,
      displayName: name,
      phoneNumber: phoneNumber,
      address: address,
    );
  }
}
