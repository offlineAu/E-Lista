import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
// `firebase_auth` re-exports `FirebaseException` from `firebase_core`, which is the base
// type every Firestore, Storage and Functions error extends.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'app_failure.dart';

/// Turns backend and platform errors into [AppFailure]s a shopkeeper can act on.
///
/// The rule this enforces: a raw exception never reaches a widget. `[cloud_firestore/
/// permission-denied] Missing or insufficient permissions.` tells a store owner nothing;
/// "You do not have permission to do that." tells them the operation was refused, and the
/// original goes to the developer log with the operation name attached.
abstract final class ErrorMapper {
  /// Maps [error] to an [AppFailure] and logs the original.
  ///
  /// [operation] names what was being attempted — `place order`, `load products` — and is
  /// used both in the log line and, for genuinely unexpected errors, in the message.
  static AppFailure map(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final failure = _classify(error, stackTrace, operation);
    _log(failure, error, stackTrace, operation);
    return failure;
  }

  /// Runs [action], mapping anything it throws.
  ///
  /// Repositories wrap their Firestore calls in this so every call site above them can
  /// assume it only ever catches [AppFailure].
  static Future<T> guard<T>(
    Future<T> Function() action, {
    required String operation,
    Duration? timeout,
  }) async {
    try {
      final future = action();
      return timeout == null ? await future : await future.timeout(timeout);
    } on AppFailure {
      rethrow; // Already translated; do not double-wrap.
    } catch (error, stackTrace) {
      throw map(error, stackTrace, operation: operation);
    }
  }

  static AppFailure _classify(
    Object error,
    StackTrace stackTrace,
    String operation,
  ) {
    if (error is AppFailure) return error;

    if (error is FirebaseAuthException) {
      return _fromAuth(error, stackTrace);
    }
    if (error is FirebaseFunctionsException) {
      return _fromFunctions(error, stackTrace, operation);
    }
    if (error is FirebaseException) {
      return _fromFirebase(error, stackTrace, operation);
    }
    if (error is TimeoutException) {
      return AppFailure(
        message:
            'This is taking longer than expected. '
            'Check your connection and try again.',
        severity: FailureSeverity.transient,
        code: 'timeout',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is SocketException || error is HttpException) {
      return AppFailure.offline(cause: error);
    }
    if (error is FormatException) {
      return AppFailure(
        message: 'We received an unexpected response. Please try again.',
        severity: FailureSeverity.transient,
        code: 'bad-response',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return AppFailure(
      message:
          'Something went wrong while we tried to $operation. '
          'Please try again.',
      code: 'unknown',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static AppFailure _fromAuth(
    FirebaseAuthException error,
    StackTrace stackTrace,
  ) {
    final (message, severity) = switch (error.code) {
      'invalid-email' => (
        'That email address does not look right.',
        FailureSeverity.userCorrectable,
      ),
      'user-disabled' => (
        'This account has been disabled. Please contact the store owner.',
        FailureSeverity.permanent,
      ),
      'user-not-found' || 'wrong-password' || 'invalid-credential' => (
        'Email or password is incorrect.',
        FailureSeverity.userCorrectable,
      ),
      'email-already-in-use' => (
        'That email already has an account. Try logging in instead.',
        FailureSeverity.userCorrectable,
      ),
      'weak-password' => (
        'Please choose a password with at least 8 characters.',
        FailureSeverity.userCorrectable,
      ),
      'requires-recent-login' => (
        'Please log in again before making this change.',
        FailureSeverity.userCorrectable,
      ),
      'credential-already-in-use' || 'provider-already-linked' => (
        'That email already has an account. Log in to it to keep shopping.',
        FailureSeverity.userCorrectable,
      ),
      'operation-not-allowed' => (
        'This sign-in method is not enabled for this store.',
        FailureSeverity.permanent,
      ),
      'too-many-requests' => (
        'Too many attempts. Please wait a moment and try again.',
        FailureSeverity.transient,
      ),
      'network-request-failed' => (
        'No internet connection. Check your connection and try again.',
        FailureSeverity.transient,
      ),
      _ => (
        'We could not sign you in right now. Please try again.',
        FailureSeverity.permanent,
      ),
    };

    return AppFailure(
      message: message,
      severity: severity,
      code: error.code,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static AppFailure _fromFunctions(
    FirebaseFunctionsException error,
    StackTrace stackTrace,
    String operation,
  ) {
    // Every callable in this app throws with a message already written for the user — out
    // of stock, price changed, tier overlap, setup code not correct. So the server's own
    // message is always the most specific thing we can show: it is passed through verbatim
    // whenever it exists, and the fallbacks below only apply when it is absent.
    final serverMessage = error.message?.trim();
    final hasUsableMessage =
        serverMessage != null &&
        serverMessage.isNotEmpty &&
        serverMessage != 'INTERNAL';

    final fallback = switch (error.code) {
      'unauthenticated' => 'Please sign in and try again.',
      'permission-denied' => 'You do not have permission to do that.',
      'not-found' =>
        'That request could not be handled. It may not be available yet.',
      'failed-precondition' || 'invalid-argument' || 'aborted' =>
        'We could not complete this. Please review the details and try again.',
      'resource-exhausted' =>
        'The store is busy right now. Please try again in a moment.',
      'deadline-exceeded' || 'unavailable' =>
        'We could not reach the store right now. Please try again.',
      _ =>
        'Something went wrong while we tried to $operation '
            '(${error.code}). Please try again.',
    };

    final severity = switch (error.code) {
      'permission-denied' || 'unauthenticated' || 'not-found' =>
        FailureSeverity.permanent,
      'resource-exhausted' || 'deadline-exceeded' || 'unavailable' =>
        FailureSeverity.transient,
      _ => FailureSeverity.userCorrectable,
    };

    return AppFailure(
      message: hasUsableMessage ? serverMessage : fallback,
      severity: severity,
      code: error.code,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static AppFailure _fromFirebase(
    FirebaseException error,
    StackTrace stackTrace,
    String operation,
  ) {
    final (message, severity) = switch (error.code) {
      'permission-denied' => (
        'You do not have permission to do that.',
        FailureSeverity.permanent,
      ),
      'unauthenticated' => (
        'Please sign in and try again.',
        FailureSeverity.permanent,
      ),
      'not-found' => (
        'That item could not be found. It may have been removed.',
        FailureSeverity.permanent,
      ),
      'already-exists' => (
        'That already exists.',
        FailureSeverity.userCorrectable,
      ),
      'unavailable' || 'deadline-exceeded' || 'network-request-failed' => (
        'We could not reach the store right now. '
            'Check your connection and try again.',
        FailureSeverity.transient,
      ),
      'resource-exhausted' => (
        'The store is busy right now. Please try again in a moment.',
        FailureSeverity.transient,
      ),
      'aborted' => (
        'Someone else changed this at the same time. Please try again.',
        FailureSeverity.transient,
      ),
      'cancelled' => (
        'That was cancelled before it finished.',
        FailureSeverity.transient,
      ),
      'unauthorized' => (
        'You do not have permission to upload that.',
        FailureSeverity.permanent,
      ),
      'object-not-found' => (
        'That image is no longer available.',
        FailureSeverity.permanent,
      ),
      _ => (
        'Something went wrong while we tried to $operation. Please try again.',
        FailureSeverity.permanent,
      ),
    };

    return AppFailure(
      message: message,
      severity: severity,
      code: error.code,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static void _log(
    AppFailure failure,
    Object error,
    StackTrace stackTrace,
    String operation,
  ) {
    developer.log(
      'Failed to $operation: ${failure.message}',
      name: 'e_lista',
      level: switch (failure.severity) {
        FailureSeverity.userCorrectable => 800, // INFO
        FailureSeverity.transient => 900, // WARNING
        FailureSeverity.permanent => 1000, // SEVERE
      },
      error: error,
      stackTrace: stackTrace,
    );

    // `developer.log` goes to the VM service stream, which nothing is listening to outside
    // DevTools — it never reaches `adb logcat` or the `flutter run` console. `debugPrint`
    // does, which is the only reason to duplicate the line here: so the failing code is
    // visible wherever the app's other native logs already are.
    debugPrint(
      'e_lista: failed to $operation — code=${failure.code} cause=$error',
    );
  }
}
