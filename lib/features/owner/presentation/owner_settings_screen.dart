import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';

/// The owner's settings hub.
///
/// Everything that changes how the store behaves, in one place, with the pricing rules
/// first because they are what an owner actually revisits.
class OwnerSettingsScreen extends ConsumerStatefulWidget {
  const OwnerSettingsScreen({super.key});

  @override
  ConsumerState<OwnerSettingsScreen> createState() =>
      _OwnerSettingsScreenState();
}

class _OwnerSettingsScreenState extends ConsumerState<OwnerSettingsScreen> {
  bool _isWorking = false;

  Future<void> _seedStore() async {
    setState(() => _isWorking = true);
    try {
      await ref.read(storeFunctionsProvider).seedStore();
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        'Default categories and settings are in place.',
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _grantOwnerAccess() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Give owner access'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'That account will be able to see costs, change prices and manage '
                'orders. They must already have an E-Lista account.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Email address'),
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
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
              Navigator.of(context).pop(emailController.text.trim());
            },
            child: const Text('Grant access'),
          ),
        ],
      ),
    );

    emailController.dispose();
    if (email == null || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await ref
          .read(storeFunctionsProvider)
          .setUserRole(email: email, role: 'owner');
      if (!mounted) return;
      showSuccessSnackBar(context, '$email now has owner access.');
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will go back to browsing as a guest. Log in again to return to '
          'the dashboard.',
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
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(currentSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerDashboard),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (session != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront),
                title: Text(session.profile.email ?? 'Store owner'),
                subtitle: Text(session.role.label),
              ),
            ),
          const SizedBox(height: 20),
          Text('Pricing', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.percent),
                  title: const Text('Profit and pricing'),
                  subtitle: const Text(
                    'The default profit percentage and how prices are worked out.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.ownerPricingSettings),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('GCash convenience fees'),
                  subtitle: const Text('The fee tiers by order size.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.ownerGcashFees),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Price history'),
                  subtitle: const Text(
                    'Every cost and price change across the store.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.ownerStorePriceHistory),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Store', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.inventory_outlined),
                  title: const Text('Inventory history'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.ownerInventoryHistory),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Set up default categories'),
                  subtitle: const Text(
                    'Adds the usual sari-sari shelves. Existing ones are left alone.',
                  ),
                  onTap: _isWorking ? null : _seedStore,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: const Text('Give someone owner access'),
                  subtitle: const Text(
                    'They will see costs, prices and sales.',
                  ),
                  onTap: _isWorking ? null : _grantOwnerAccess,
                ),
              ],
            ),
          ),
          if (AppConfig.isDevelopmentBackend) ...[
            const SizedBox(height: 20),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.developer_mode,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This build is running against the local Firebase '
                        'emulators. Nothing here is real store data.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Log out',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: _isWorking ? null : _signOut,
            ),
          ),
        ],
      ),
    );
  }
}
