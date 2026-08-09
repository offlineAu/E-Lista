import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/utils/validators.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/app_logo.dart';
import '../../../widgets/state_views.dart';
import '../application/auth_controller.dart';

/// Email and password sign-in, for returning customers and for the store owner.
///
/// There is no separate owner login screen. The role comes from the account's custom
/// claim, so signing in as the owner here lands on the dashboard, and signing in as a
/// customer lands on the shelves — the same form either way.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final controller = ref.read(authControllerProvider.notifier);
    await controller.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;
    if (!ref.read(authControllerProvider).hasError) {
      // The router sends an owner to the dashboard and a customer to the shelves.
      context.go(AppRoutes.splash);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (Validators.email(email) != null) {
      showFailureSnackBar(
        context,
        const AppFailure.invalidInput(
          'Enter your email address first, then tap Forgot password.',
        ),
      );
      return;
    }

    await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
    if (!mounted) return;
    if (!ref.read(authControllerProvider).hasError) {
      showSuccessSnackBar(context, 'Password reset email sent to $email.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(authControllerProvider);
    final isBusy = state.isLoading;

    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        showFailureSnackBar(context, next.error!);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Log in')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(size: 72)),
                    const SizedBox(height: 20),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      enabled: !isBusy,
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      enabled: !isBusy,
                      validator: (value) =>
                          Validators.required(value, field: 'Password'),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isBusy ? null : _resetPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: isBusy ? null : _submit,
                      child: isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Log in'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'New here?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: isBusy
                              ? null
                              : () =>
                                    context.pushReplacement(AppRoutes.register),
                          child: const Text('Create an account'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
