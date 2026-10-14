import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../routing/app_routes.dart';
import '../../../services/store_functions_service.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/price_display.dart';
import '../../../widgets/state_views.dart';
import '../application/shift_providers.dart';
import 'widgets/cashier_logout_action.dart';

/// A cash-drawer snapshot at the end of a shift: what today's cash sales should have added
/// up to, against what was actually counted.
///
/// A snapshot, not a shift clock — there is no clock-in/clock-out state here, just an audit
/// row the owner can review afterward.
class ShiftSummaryScreen extends ConsumerStatefulWidget {
  const ShiftSummaryScreen({super.key});

  @override
  ConsumerState<ShiftSummaryScreen> createState() => _ShiftSummaryScreenState();
}

class _ShiftSummaryScreenState extends ConsumerState<ShiftSummaryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _countedController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isSaving = false;
  RecordedCashCount? _recorded;

  @override
  void dispose() {
    _countedController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit(Money expected) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final counted = Money.tryParse(_countedController.text);
    if (counted == null) return;

    setState(() => _isSaving = true);
    try {
      final recorded = await ref
          .read(storeFunctionsProvider)
          .recordCashCount(
            expected: expected,
            counted: counted,
            note: _noteController.text,
          );
      if (!mounted) return;
      setState(() {
        _recorded = recorded;
        _isSaving = false;
      });
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
      setState(() => _isSaving = false);
    }
  }

  void _startOver() {
    _countedController.clear();
    _noteController.clear();
    setState(() => _recorded = null);
    ref.invalidate(todaysShiftSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(todaysShiftSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('End of shift'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerPosCheckout),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        actions: const [CashierLogoutAction()],
      ),
      body: _recorded != null
          ? _ShiftResultView(recorded: _recorded!, onDone: _startOver)
          : AsyncView<ShiftCashSummary>(
              value: summary,
              onRetry: () => ref.invalidate(todaysShiftSummaryProvider),
              builder: (context, value) => _ShiftForm(
                summary: value,
                formKey: _formKey,
                countedController: _countedController,
                noteController: _noteController,
                isSaving: _isSaving,
                onSubmit: () => _submit(value.expectedCash),
              ),
            ),
    );
  }
}

class _ShiftForm extends StatelessWidget {
  const _ShiftForm({
    required this.summary,
    required this.formKey,
    required this.countedController,
    required this.noteController,
    required this.isSaving,
    required this.onSubmit,
  });

  final ShiftCashSummary summary;
  final GlobalKey<FormState> formKey;
  final TextEditingController countedController;
  final TextEditingController noteController;
  final bool isSaving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Your shift', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ShiftStat(
                  label: 'Sales',
                  value: '${summary.salesCount}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ShiftStat(
                  label: 'Total rung up',
                  value: summary.totalRungUp.format(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ShiftStat(
                  label: 'Items',
                  value: '${summary.itemCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text("Today's cash sales", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              children: [
                PriceRow(
                  label: 'Expected in the drawer',
                  amount: summary.expectedCash,
                  note:
                      '${summary.cashSalesCount} '
                      '${summary.cashSalesCount == 1 ? 'cash sale' : 'cash sales'}',
                  emphasised: true,
                ),
                const Divider(height: 20),
                PriceRow(
                  label: 'GCash collected (not in the drawer)',
                  amount: summary.gcashCollected,
                  note:
                      '${summary.gcashSalesCount} '
                      '${summary.gcashSalesCount == 1 ? 'GCash sale' : 'GCash sales'}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Count the drawer', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: countedController,
            decoration: const InputDecoration(
              labelText: 'Amount counted (₱)',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !isSaving,
            validator: (value) => Validators.money(value, field: 'Amount counted'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: countedController,
            builder: (context, value, _) {
              final counted = Money.tryParse(value.text);
              if (counted == null) return const SizedBox.shrink();

              final difference = counted - summary.expectedCash;
              final isShort = difference.isNegative;
              final isExact = difference.isZero;
              final color = isExact
                  ? theme.colorScheme.primary
                  : isShort
                  ? theme.colorScheme.error
                  : theme.colorScheme.secondary;
              final label = isExact
                  ? 'Matches exactly'
                  : isShort
                  ? 'Short by ${(-difference).format()}'
                  : 'Over by ${difference.format()}';

              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              prefixIcon: Icon(Icons.edit_note_outlined),
              helperText: 'Anything that explains a difference — a refund paid from '
                  'the drawer, a miscount caught late.',
            ),
            maxLines: 2,
            enabled: !isSaving,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: isSaving ? null : onSubmit,
            child: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Record cash count'),
          ),
        ],
      ),
    );
  }
}

/// One figure in the "Your shift" row — a count or a total, not a comparison.
class _ShiftStat extends StatelessWidget {
  const _ShiftStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftResultView extends StatelessWidget {
  const _ShiftResultView({required this.recorded, required this.onDone});

  final RecordedCashCount recorded;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final difference = recorded.difference;
    final isShort = difference.isNegative;
    final isExact = difference.isZero;

    final statusColor = isExact
        ? theme.colorScheme.primary
        : isShort
        ? theme.colorScheme.error
        : theme.colorScheme.secondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isExact
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 56,
              color: statusColor,
            ),
            const SizedBox(height: 16),
            Text(
              isExact
                  ? 'Drawer matches exactly'
                  : isShort
                  ? 'Short by ${(-difference).format()}'
                  : 'Over by ${difference.format()}',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GlassCard(
              child: Column(
                children: [
                  PriceRow(label: 'Expected', amount: recorded.expected),
                  PriceRow(label: 'Counted', amount: recorded.counted),
                  const Divider(height: 20),
                  PriceRow(
                    label: 'Difference',
                    amount: difference,
                    emphasised: true,
                    amountColor: statusColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
