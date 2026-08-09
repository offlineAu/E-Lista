import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_mapper.dart';

/// The three states every asynchronous screen in the app has to be able to show.
///
/// They live together so they stay consistent: the same spacing, the same icon size, the
/// same tone of voice. A screen that invents its own empty state is how an app starts
/// feeling like several apps.

/// A centred progress indicator with an optional label.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message, this.compact = false});

  final String? message;

  /// Uses less vertical space, for loading inside a card or a sheet.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 16 : 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An error state written for the person holding the phone.
///
/// It shows [AppFailure.message] — already plain language — and offers Retry only when
/// retrying could actually help. A permission error gets no Retry button, because pressing
/// it would just fail again.
class ErrorView extends StatelessWidget {
  const ErrorView({
    required this.failure,
    super.key,
    this.onRetry,
    this.compact = false,
  });

  /// Builds from any error, translating it if it has not been translated already.
  factory ErrorView.from(
    Object error,
    StackTrace? stackTrace, {
    VoidCallback? onRetry,
    bool compact = false,
  }) {
    final failure = error is AppFailure
        ? error
        : ErrorMapper.map(
            error,
            stackTrace ?? StackTrace.current,
            operation: 'load this',
          );
    return ErrorView(failure: failure, onRetry: onRetry, compact: compact);
  }

  final AppFailure failure;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRetry = onRetry != null && failure.isRetryable;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 16 : 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconFor(failure.severity),
              size: compact ? 32 : 44,
              color: theme.colorScheme.error,
              semanticLabel: 'Error',
            ),
            const SizedBox(height: 16),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (canRetry) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ] else if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton(onPressed: onRetry, child: const Text('Reload')),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(FailureSeverity severity) => switch (severity) {
    FailureSeverity.transient => Icons.wifi_off_rounded,
    FailureSeverity.userCorrectable => Icons.info_outline_rounded,
    FailureSeverity.permanent => Icons.error_outline_rounded,
  };
}

/// An empty state that says what is missing and what to do next.
///
/// "No products found." on its own leaves a shopper stuck; the [action] and the hint are
/// what make the screen usable.
class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.title,
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 32,
          vertical: compact ? 16 : 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 36 : 52,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue] as loading, error or data — the three states, every time.
///
/// Using this rather than `asyncValue.when(...)` at each call site is what stops a screen
/// from quietly forgetting its error branch and showing a spinner forever.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.value,
    required this.builder,
    super.key,
    this.onRetry,
    this.loadingMessage,
    this.compact = false,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final String? loadingMessage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (data) => builder(context, data),
      loading: () => LoadingView(message: loadingMessage, compact: compact),
      error: (error, stackTrace) =>
          ErrorView.from(error, stackTrace, onRetry: onRetry, compact: compact),
    );
  }
}

/// Shows a failure as a snackbar, for actions that do not replace the whole screen.
void showFailureSnackBar(BuildContext context, Object error) {
  final failure = error is AppFailure
      ? error
      : ErrorMapper.map(error, StackTrace.current, operation: 'do that');

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failure.message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
}

/// Shows a short confirmation.
void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
}
