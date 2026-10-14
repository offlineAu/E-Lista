import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/app_logo.dart';
import '../../../widgets/state_views.dart';
import '../application/auth_controller.dart';

/// Creating an account.
///
/// For a guest — which is most people who reach this screen, having already shopped — this
/// **links** an email to the anonymous account they are already using. The uid does not
/// change, so their cart and every order they placed stay theirs. The screen says so,
/// because "will I lose my basket?" is the reason people do not sign up.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.reason});

  /// Why the app asked. Passed as `?reason=` when the prompt comes after an order, so the
  /// screen can lead with "keep your order history" rather than a generic invitation.
  final String? reason;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentSessionProvider)?.profile;
    final existingName = profile?.displayName?.trim();
    if (existingName != null && existingName.isNotEmpty) {
      _nameController.text = existingName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(authControllerProvider.notifier)
        .register(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _nameController.text,
        );

    if (!mounted) return;
    if (!ref.read(authControllerProvider).hasError) {
      // Same race as login_screen.dart's _submit: the router's redirect reads
      // authSessionProvider synchronously the instant context.go fires below, and
      // registering does not by itself rebuild that cached session.
      final _ = await ref.refresh(authSessionProvider.future);
      if (!mounted) return;
      showSuccessSnackBar(context, 'Your account is ready.');
      context.go(AppRoutes.splash);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(authControllerProvider);
    final isBusy = state.isLoading;
    final isGuest = ref.watch(isGuestProvider);

    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        showFailureSnackBar(context, next.error!);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Create an account')),
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
                    const Center(child: AppLogo(size: 64)),
                    const SizedBox(height: 18),
                    Text(
                      widget.reason == 'order'
                          ? 'Keep your order history'
                          : 'Create your account',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    if (isGuest) _KeepEverythingNote(theme: theme),
                    if (isGuest) const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      enabled: !isBusy,
                      validator: Validators.personName,
                    ),
                    const SizedBox(height: 16),
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
                        helperText: 'At least 8 characters.',
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
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      enabled: !isBusy,
                      validator: Validators.password,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      enabled: !isBusy,
                      validator: (value) => Validators.confirmPassword(
                        value,
                        _passwordController.text,
                      ),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
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
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have one?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: isBusy
                              ? null
                              : () => context.pushReplacement(AppRoutes.login),
                          child: const Text('Log in'),
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

class _KeepEverythingNote extends StatelessWidget {
  const _KeepEverythingNote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.shopping_basket_outlined,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your cart and every order you have placed stay with you. '
                'Creating an account adds a way to log in — it does not start you over.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
