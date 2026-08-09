import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

/// What a signed-in user is allowed to do.
///
/// The authoritative copy of this lives in the Firebase Auth custom claim `role`, which
/// security rules read. The copy in `users/{uid}.role` exists so the app can show the
/// right screens, and is written only by a Cloud Function that sets both together. A
/// client that edits its own `users` document cannot change its role: the rules reject a
/// write that alters the field, and the rules that matter check the claim, not the
/// document.
enum UserRole {
  /// Browsing without an account, signed in anonymously. Can shop and order.
  guest,

  /// A registered shopper.
  customer,

  /// The store owner. Sees costs, inventory, sales and settings.
  owner;

  static UserRole fromJson(Object? value) => switch (value) {
    'owner' => UserRole.owner,
    'guest' => UserRole.guest,
    _ => UserRole.customer,
  };

  String toJson() => name;

  /// True for both guests and registered shoppers.
  bool get isCustomer => this != UserRole.owner;

  bool get isOwner => this == UserRole.owner;

  bool get isGuest => this == UserRole.guest;

  String get label => switch (this) {
    UserRole.guest => 'Guest',
    UserRole.customer => 'Customer',
    UserRole.owner => 'Store owner',
  };
}

/// The application's view of a signed-in user.
///
/// A guest has a real Firebase uid (from anonymous auth) and a real profile document, so
/// their cart and orders behave exactly like a registered customer's. The difference is
/// only that the account has no permanent credential yet — see the guest-conversion flow,
/// which links an email to the same uid and keeps everything.
@immutable
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.role,
    required this.isAnonymous,
    this.displayName,
    this.email,
    this.phoneNumber,
    this.address,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final UserRole role;

  /// True while the account is a Firebase anonymous account.
  final bool isAnonymous;

  final String? displayName;
  final String? email;
  final String? phoneNumber;

  /// Delivery address, captured at checkout and reused for later orders.
  final String? address;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOwner => role.isOwner;
  bool get isCustomer => role.isCustomer;

  /// True when the account can still be upgraded by linking a permanent credential.
  bool get canBecomePermanent => isAnonymous;

  /// What to greet the person with. Falls back through the identifiers we have.
  String get greetingName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail.split('@').first;
    return 'there';
  }

  /// Whether checkout can be completed without asking for contact details again.
  bool get hasContactDetails =>
      (displayName?.trim().isNotEmpty ?? false) &&
      (phoneNumber?.trim().isNotEmpty ?? false);

  UserProfile copyWith({
    UserRole? role,
    bool? isAnonymous,
    Object? displayName = _unset,
    Object? email = _unset,
    Object? phoneNumber = _unset,
    Object? address = _unset,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      role: role ?? this.role,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      displayName: identical(displayName, _unset)
          ? this.displayName
          : displayName as String?,
      email: identical(email, _unset) ? this.email : email as String?,
      phoneNumber: identical(phoneNumber, _unset)
          ? this.phoneNumber
          : phoneNumber as String?,
      address: identical(address, _unset) ? this.address : address as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// The document a client is allowed to write.
  ///
  /// `role` is included because the rules require it to be unchanged on update and equal
  /// to `customer` on create; it is never a way to grant yourself ownership.
  Map<String, Object?> toJson() => {
    'uid': uid,
    'role': role.toJson(),
    'isAnonymous': isAnonymous,
    'displayName': displayName,
    'email': email,
    'phoneNumber': phoneNumber,
    'address': address,
    'createdAt': createdAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(createdAt!),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static UserProfile fromJson(String uid, Map<String, Object?> json) {
    return UserProfile(
      uid: uid,
      role: UserRole.fromJson(json['role']),
      isAnonymous: (json['isAnonymous'] as bool?) ?? false,
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      address: json['address'] as String?,
      createdAt: _readTimestamp(json['createdAt']),
      updatedAt: _readTimestamp(json['updatedAt']),
    );
  }

  static DateTime? _readTimestamp(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    DateTime() => value,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.uid == uid &&
      other.role == role &&
      other.isAnonymous == isAnonymous &&
      other.displayName == displayName &&
      other.email == email &&
      other.phoneNumber == phoneNumber &&
      other.address == address;

  @override
  int get hashCode => Object.hash(
    uid,
    role,
    isAnonymous,
    displayName,
    email,
    phoneNumber,
    address,
  );

  @override
  String toString() =>
      'UserProfile($uid, ${role.name}, anonymous: $isAnonymous)';

  static const Object _unset = Object();
}
