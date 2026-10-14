import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/percentage.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../models/pricing_settings.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../../pricing/domain/pricing_engine.dart';

/// The store's default profit percentage, and an explanation of what it does.
///
/// Cash and GCash share the same markup, so the screen works through a live example rather
/// than stating the rule: an owner who can see that ₱15 at 20% becomes ₱18 either way
/// understands the setting immediately.
class PricingSettingsScreen extends ConsumerStatefulWidget {
  const PricingSettingsScreen({super.key});

  @override
  ConsumerState<PricingSettingsScreen> createState() =>
      _PricingSettingsScreenState();
}

class _PricingSettingsScreenState extends ConsumerState<PricingSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profitController = TextEditingController();
  bool _isSaving = false;
  bool _hasLoaded = false;

  @override
  void dispose() {
    _profitController.dispose();
    super.dispose();
  }

  void _load(PricingSettings settings) {
    if (_hasLoaded) return;
    _hasLoaded = true;
    _profitController.text = settings.defaultProfitPercentage
        .format()
        .replaceAll('%', '');
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final percentage = Percentage.tryParse(_profitController.text);
    if (percentage == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-price the store?'),
        content: Text(
          'Every product set to the store default will be re-priced at '
          '${percentage.format()}. Products with their own percentage are left '
          'alone.\n\nPast orders keep the prices customers actually paid.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Re-price'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final count = await ref
          .read(storeFunctionsProvider)
          .savePricingSettings(percentage);
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        count == 0
            ? 'Saved. No product prices changed.'
            : 'Saved. $count ${count == 1 ? 'product was' : 'products were'} '
                  're-priced.',
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(pricingSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing settings'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerSettings),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: AsyncView<PricingSettings>(
        value: settings,
        onRetry: () => ref.invalidate(pricingSettingsProvider),
        builder: (context, value) {
          _load(value);
          return _Body(
            formKey: _formKey,
            controller: _profitController,
            isSaving: _isSaving,
            onSave: _save,
            onChanged: () => setState(() {}),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.formKey,
    required this.controller,
    required this.isSaving,
    required this.onSave,
    required this.onChanged,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = Percentage.tryParse(controller.text);

    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Default profit', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'New products use this, and so does every existing product set to '
            '"store default".',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Default profit (%)',
              prefixIcon: Icon(Icons.percent),
              helperText: 'For example 20 or 20.5.',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !isSaving,
            validator: (value) => Validators.profitPercentage(
              value,
              maximumBasisPoints: PricingSettings.maximumProfitBasisPoints,
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 24),
          if (percentage != null &&
              !percentage.isNegative &&
              percentage.basisPoints < PricingSettings.maximumProfitBasisPoints)
            _WorkedExample(percentage: percentage, theme: theme),
          const SizedBox(height: 24),
          _RuleCard(
            theme: theme,
            title: 'Cash uses a markup',
            body:
                'The percentage is added on top of what you paid, then the '
                'price drops to a whole peso. ₱17 at 20% works out to ₱20.40, '
                'so the price is ₱20 — never ₱21. Coins, not centavos.',
            icon: Icons.payments_outlined,
          ),
          const SizedBox(height: 12),
          _RuleCard(
            theme: theme,
            title: 'GCash prices the same way',
            body:
                'GCash and cash use the same markup, so the per-product price is '
                'the same either way. ₱15 at 20% is ₱18 for both. The GCash '
                'convenience fee is then added once per order.',
            icon: Icons.account_balance_wallet_outlined,
          ),
          const SizedBox(height: 12),
          _RuleCard(
            theme: theme,
            title: 'A product can ignore this',
            body:
                'Set a product to "custom" and it keeps its own percentage. '
                'Changing the store default will not move it.',
            icon: Icons.tune,
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('GCash convenience fees'),
              subtitle: const Text(
                'The fee added once per GCash order, by order size.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.ownerGcashFees),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: isSaving ? null : onSave,
            child: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Save and re-price'),
          ),
        ],
      ),
    );
  }
}

/// The same cost priced both ways, updating as the owner types.
class _WorkedExample extends StatelessWidget {
  const _WorkedExample({required this.percentage, required this.theme});

  final Percentage percentage;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    const exampleCost = Money.fromPesos(15);
    final prices = PricingEngine.pricesFor(
      cost: exampleCost,
      profitPercentage: percentage,
    );

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'At ${percentage.format()}, a product that cost you '
              '${exampleCost.format()} sells for:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            DualPriceView(cashPrice: prices.cash, gcashPrice: prices.gcashBase),
            const SizedBox(height: 14),
            Text(
              'You keep ${(prices.cash - exampleCost).format()} on a cash sale '
              'and ${(prices.gcashBase - exampleCost).format()} on a GCash one, '
              'before the convenience fee.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.theme,
    required this.title,
    required this.body,
    required this.icon,
  });

  final ThemeData theme;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
