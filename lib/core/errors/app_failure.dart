import 'package:meta/meta.dart';

/// How severe a failure is, which decides how the UI surfaces it.
enum FailureSeverity {
  /// The user can fix it themselves — bad input, a duplicate barcode, empty cart.
  /// Shown inline, next to the thing that is wrong.
  userCorrectable,

  /// Temporary and worth retrying — no connection, a timeout, a busy backend.
  /// Shown with a Retry action.
  transient,

  /// The operation is not allowed, or something is genuinely broken.
  /// Shown as a message; retrying will not help.
  permanent,
}

/// A failure that has already been translated into something a shopkeeper can read.
///
/// Nothing in the UI layer ever sees a `FirebaseException`, a `SocketException` or a
/// stack trace: repositories and services catch those and rethrow an [AppFailure] whose
/// [message] is plain language and whose [severity] tells the UI whether to offer Retry.
/// The original error is kept in [cause] for logs, never for display.
@immutable
class AppFailure implements Exception {
  const AppFailure({
    required this.message,
    this.severity = FailureSeverity.permanent,
    this.code,
    this.cause,
    this.stackTrace,
  });

  /// Something the user typed or chose cannot be accepted.
  const AppFailure.invalidInput(String message, {String? code})
    : this(
        message: message,
        severity: FailureSeverity.userCorrectable,
        code: code,
      );

  /// The device or the backend could not be reached right now.
  const AppFailure.offline({
    String message =
        'No internet connection. Check your connection and try again.',
    Object? cause,
  }) : this(
         message: message,
         severity: FailureSeverity.transient,
         code: 'offline',
         cause: cause,
       );

  /// The signed-in user is not allowed to do this.
  const AppFailure.notAllowed([
    String message = 'You do not have permission to do that.',
  ]) : this(
         message: message,
         severity: FailureSeverity.permanent,
         code: 'permission-denied',
       );

  /// The thing being read no longer exists.
  const AppFailure.notFound([String message = 'That item could not be found.'])
    : this(
        message: message,
        severity: FailureSeverity.permanent,
        code: 'not-found',
      );

  /// Plain language, addressed to the user, describing what did not happen and what to
  /// do about it. Never a raw exception string.
  final String message;

  final FailureSeverity severity;

  /// A stable identifier for logs and tests, e.g. `permission-denied`, `out-of-stock`.
  final String? code;

  /// The underlying error, for developer logs only.
  final Object? cause;

  final StackTrace? stackTrace;

  /// Whether the UI should offer a Retry action.
  bool get isRetryable => severity == FailureSeverity.transient;

  AppFailure copyWith({
    String? message,
    FailureSeverity? severity,
    String? code,
  }) {
    return AppFailure(
      message: message ?? this.message,
      severity: severity ?? this.severity,
      code: code ?? this.code,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('AppFailure(${severity.name}')
      ..write(code == null ? '' : ', $code')
      ..write('): $message');
    if (cause != null) buffer.write(' — caused by: $cause');
    return buffer.toString();
  }
}
