import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../models/user_profile.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/app_logo.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';

/// The shopper's own details, and the way out of the app.
///
/// A guest sees the same screen with an invitation to create an account instead of a sign
/// out button — their details are still theirs, and editing them here means checkout does
/// not have to ask twice.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentSessionProvider)?.profile;
    _nameController = TextEditingController(text: profile?.displayName ?? '');
    _phoneController = TextEditingController(text: profile?.phoneNumber ?? '');
    _addressController = TextEditingController(text: profile?.address ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save(UserProfile profile) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .updateContactDetails(
            profile.uid,
            displayName: _nameController.text,
            phoneNumber: _phoneController.text,
            address: _addressController.text,
          );
      if (!mounted) return;
      showSuccessSnackBar(context, 'Your details are saved.');
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Takes over as the store owner using the one-time setup code.
  ///
  /// The code only works while the store has no owner, and only for an account with a real
  /// credential — an anonymous session cannot be the thing that runs a shop. Ownership
  /// arrives as a custom claim, so the ID token has to be refreshed before the app will
  /// show owner screens or Firestore will serve owner data.
  Future<void> _claimStore() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Take over this store'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The setup code was configured when this app was deployed. '
                'It works once, for the first owner only.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Setup code'),
                validator: (value) =>
                    Validators.required(value, field: 'Setup code'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.of(context).pop(controller.text.trim());
            },
            child: const Text('Claim'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (code == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(storeFunctionsProvider).claimStoreOwnership(code);
      // The claim is on the ID token, which is cached for up to an hour. Refresh it now,
      // or the app would keep showing customer screens to the owner.
      await ref
          .read(authServiceProvider)
          .resolveRole(
            ref.read(firebaseAuthProvider).currentUser!,
            forceRefresh: true,
          );
      await ref.read(authServiceProvider).refresh();

      if (!mounted) return;
      showSuccessSnackBar(context, 'You are now the store owner.');
      context.go(AppRoutes.ownerDashboard);
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will keep browsing as a guest. Your order history stays with '
          'your account and comes back when you log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay logged in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (!mounted) return;
    if (ref.read(authControllerProvider).hasError) {
      showFailureSnackBar(context, ref.read(authControllerProvider).error!);
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return const Scaffold(body: LoadingView());
    }

    final profile = session.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                const AppLogo(size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.isGuest
                            ? 'Shopping as a guest'
                            : (profile.displayName?.trim().isNotEmpty ?? false)
                            ? profile.displayName!
                            : 'Your account',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (profile.email != null)
                        Text(
                          profile.email!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        session.role.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (session.isGuest) ...[
              _CreateAccountCard(theme: theme),
              const SizedBox(height: 24),
            ],
            Text('Your details', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'We use these to contact you about an order. '
              'Saving them here means checkout does not ask again.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_isSaving,
              validator: Validators.personName,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: Icon(Icons.phone_outlined),
                helperText: 'For example 0917 123 4567',
              ),
              keyboardType: TextInputType.phone,
              enabled: !_isSaving,
              validator: (value) =>
                  Validators.phoneNumber(value, isRequired: false),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Delivery address',
                prefixIcon: Icon(Icons.home_outlined),
                helperText: 'Leave empty if you pick up at the store.',
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSaving ? null : () => _save(profile),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Save details'),
            ),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Your orders'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.orders),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan a product'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.customerScan),
            ),
            if (!session.isGuest)
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('I run this store'),
                subtitle: const Text(
                  'Enter the setup code to take over as owner.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _claimStore,
              ),
            if (!session.isGuest)
              ListTile(
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text(
                  'Log out',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: _signOut,
              ),
          ],
        ),
      ),
    );
  }
}

class _CreateAccountCard extends StatelessWidget {
  const _CreateAccountCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keep your cart and orders',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Creating an account adds a way to log in from another phone. '
              'Everything you have now comes with you.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton(
                  onPressed: () => context.push(AppRoutes.register),
                  child: const Text('Create account'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => context.push(AppRoutes.login),
                  child: const Text('Log in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
