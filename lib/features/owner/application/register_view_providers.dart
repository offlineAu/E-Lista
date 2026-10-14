import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the owner has switched the shell to the compact cashier-style layout.
///
/// In-memory only — resets on app restart — and purely cosmetic: it changes which
/// destinations `OwnerShell` renders, nothing about the owner's role, claims, or what any
/// route or Firestore rule permits. A real cashier's shell already shows this layout
/// unconditionally regardless of this provider.
final viewAsCashierProvider = StateProvider<bool>((ref) => false);
