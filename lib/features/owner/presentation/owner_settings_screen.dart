import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/register_view_providers.dart';

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

  Future<void> _pickAndSaveQr({required bool fromCamera}) async {
    try {
      final picked = await ref
          .read(gcashQrImageServiceProvider)
          .pick(fromCamera: fromCamera);
      if (picked == null || !mounted) return;

      setState(() => _isWorking = true);
      final url = await ref.read(gcashQrImageServiceProvider).upload(picked);
      await ref.read(storeFunctionsProvider).saveGcashQr(url);
      if (!mounted) return;
      showSuccessSnackBar(context, 'GCash QR code saved.');
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _removeQr() async {
    setState(() => _isWorking = true);
    try {
      await ref.read(storeFunctionsProvider).saveGcashQr(null);
      if (!mounted) return;
      showSuccessSnackBar(context, 'GCash QR code removed.');
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  static const Map<String, String> _roleDescriptions = {
    'owner':
        'They will see costs, change prices, and manage orders, inventory, '
        'and other staff.',
    'cashier':
        "They will process orders and record stock movements, but won't see "
        'costs, change prices, or manage other staff.',
    'customer': 'They will go back to being an ordinary customer.',
  };

  Future<void> _manageAccess() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var selectedRole = 'owner';

    final result = await showDialog<(String email, String role)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Manage staff access'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: emailController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Email address'),
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: selectedRole,
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedRole = value);
                  },
                  child: Column(
                    children: [
                      for (final entry in const [
                        ('owner', 'Owner'),
                        ('cashier', 'Cashier'),
                        ('customer', 'Remove access'),
                      ])
                        RadioListTile<String>(
                          value: entry.$1,
                          title: Text(entry.$2),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
                Text(
                  _roleDescriptions[selectedRole]!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'They must already have an E-Lista account.',
                  style: TextStyle(fontStyle: FontStyle.italic),
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
                Navigator.of(
                  context,
                ).pop((emailController.text.trim(), selectedRole));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    emailController.dispose();
    if (result == null || !mounted) return;
    final (email, role) = result;

    setState(() => _isWorking = true);
    try {
      await ref
          .read(storeFunctionsProvider)
          .setUserRole(email: email, role: role);
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        role == 'customer'
            ? "$email's staff access has been removed."
            : '$email now has ${role == 'owner' ? 'owner' : 'cashier'} access.',
      );
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
    final qr = ref.watch(gcashQrProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          // In register view the dashboard is not one of the shell's own tabs, so going
          // back there instead of to the register screen would leave the bottom nav
          // highlighting the wrong tab for where the owner actually lands.
          onPressed: () => context.go(
            ref.read(viewAsCashierProvider)
                ? AppRoutes.ownerPosCheckout
                : AppRoutes.ownerDashboard,
          ),
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
          Text('Payments', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GCash QR code', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Shown to customers and the cashier at GCash checkout. Upload the '
                    'QR your own GCash app already generates — Profile > My QR Code.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 84,
                          height: 84,
                          child: (qr?.hasImage ?? false)
                              ? CachedNetworkImage(
                                  imageUrl: qr!.imageUrl!,
                                  fit: BoxFit.cover,
                                )
                              : ColoredBox(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  child: Icon(
                                    Icons.qr_code_2,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _isWorking
                                  ? null
                                  : () => _pickAndSaveQr(fromCamera: true),
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                size: 18,
                              ),
                              label: const Text('Camera'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isWorking
                                  ? null
                                  : () => _pickAndSaveQr(fromCamera: false),
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 18,
                              ),
                              label: const Text('Gallery'),
                            ),
                            if (qr?.hasImage ?? false)
                              TextButton.icon(
                                onPressed: _isWorking ? null : _removeQr,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                label: const Text('Remove'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
                  title: const Text('Manage staff access'),
                  subtitle: const Text(
                    'Grant owner or cashier access, or remove it.',
                  ),
                  onTap: _isWorking ? null : _manageAccess,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: ref.watch(viewAsCashierProvider),
                  onChanged: (value) {
                    ref.read(viewAsCashierProvider.notifier).state = value;
                    if (value) context.go(AppRoutes.ownerPosCheckout);
                  },
                  secondary: const Icon(Icons.point_of_sale_outlined),
                  title: const Text('Switch to register view'),
                  subtitle: const Text(
                    'Shows the compact Orders / Inventory / New sale layout for '
                    'working at the counter.',
                  ),
                  contentPadding: EdgeInsets.zero,
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
