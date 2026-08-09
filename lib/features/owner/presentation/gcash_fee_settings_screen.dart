import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/validators.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/state_views.dart';
import '../../pricing/domain/gcash_fee_schedule.dart';

/// Editing the GCash convenience fee table.
///
/// The tiers are data, not code: they live in Firestore and nothing in the UI hard-codes
/// an amount. What the UI does enforce, continuously while the owner edits, is that the
/// table stays *answerable* — starting at ₱0, ending open-ended, with no gap or overlap —
/// because a subtotal with two possible fees, or none, is a checkout that cannot proceed.
class GcashFeeSettingsScreen extends ConsumerStatefulWidget {
  const GcashFeeSettingsScreen({super.key});

  @override
  ConsumerState<GcashFeeSettingsScreen> createState() =>
      _GcashFeeSettingsScreenState();
}

class _GcashFeeSettingsScreenState
    extends ConsumerState<GcashFeeSettingsScreen> {
  List<GcashFeeTier>? _tiers;
  bool _isSaving = false;

  void _load(GcashFeeSchedule schedule) {
    _tiers ??= [...schedule.tiers];
  }

  String? get _problem =>
      _tiers == null ? null : GcashFeeSchedule.describeProblem(_tiers!);

  Future<void> _save() async {
    final tiers = _tiers;
    if (tiers == null || _problem != null) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(storeFunctionsProvider)
          .saveGcashFeeTiers(GcashFeeSchedule.validated(tiers));
      if (!mounted) return;
      showSuccessSnackBar(context, 'GCash fees saved.');
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editTier(int index) async {
    final tiers = _tiers;
    if (tiers == null) return;

    final edited = await showModalBottomSheet<GcashFeeTier>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _TierEditor(tier: tiers[index], isLast: index == tiers.length - 1),
    );

    if (edited == null || !mounted) return;
    setState(() => tiers[index] = edited);
  }

  Future<void> _addTier() async {
    final tiers = _tiers;
    if (tiers == null || tiers.isEmpty) return;

    // A new tier slots in just below the open-ended one, starting a peso above where the
    // previous band ends — the arrangement that is already valid, so the owner is not
    // handed an error before typing anything.
    final last = tiers.last;
    final previous = tiers.length >= 2 ? tiers[tiers.length - 2] : null;
    final newMin = previous?.max == null
        ? last.min
        : previous!.max! + const Money.fromCentavos(1);
    final newMax = newMin + const Money.fromCentavos(9999);

    setState(() {
      tiers
        ..insert(
          tiers.length - 1,
          GcashFeeTier(min: newMin, max: newMax, fee: last.fee),
        )
        ..[tiers.length - 1] = last.copyWith(
          min: newMax + const Money.fromCentavos(1),
        );
    });
  }

  void _removeTier(int index) {
    final tiers = _tiers;
    if (tiers == null || tiers.length <= 1) return;

    setState(() {
      final removed = tiers.removeAt(index);
      // Close the hole the removal left, so the table stays gapless.
      if (index < tiers.length) {
        tiers[index] = tiers[index].copyWith(min: removed.min);
      } else if (tiers.isNotEmpty) {
        tiers[tiers.length - 1] = tiers[tiers.length - 1].copyWith(max: null);
      }
    });
  }

  void _resetToDefaults() {
    setState(() => _tiers = [...GcashFeeSchedule.defaultSchedule.tiers]);
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(gcashFeeScheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GCash fees'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.ownerPricingSettings),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _resetToDefaults,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: AsyncView<GcashFeeSchedule>(
        value: schedule,
        onRetry: () => ref.invalidate(gcashFeeScheduleProvider),
        builder: (context, value) {
          _load(value);
          return _Body(
            tiers: _tiers!,
            problem: _problem,
            isSaving: _isSaving,
            onEdit: _editTier,
            onRemove: _removeTier,
            onAdd: _addTier,
            onSave: _save,
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.tiers,
    required this.problem,
    required this.isSaving,
    required this.onEdit,
    required this.onRemove,
    required this.onAdd,
    required this.onSave,
  });

  final List<GcashFeeTier> tiers;
  final String? problem;
  final bool isSaving;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'One fee is added per GCash order, not per item. Which fee '
                    'depends on the order subtotal before the fee.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        for (var index = 0; index < tiers.length; index++)
          _TierRow(
            tier: tiers[index],
            index: index,
            canRemove: tiers.length > 1,
            onEdit: () => onEdit(index),
            onRemove: () => onRemove(index),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: isSaving ? null : onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add a tier'),
        ),
        if (problem != null) ...[
          const SizedBox(height: 20),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      problem!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: isSaving || problem != null ? null : onSave,
          child: isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Save fees'),
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Fix the problem above before saving.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.index,
    required this.canRemove,
    required this.onEdit,
    required this.onRemove,
  });

  final GcashFeeTier tier;
  final int index;
  final bool canRemove;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tier.rangeLabel, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Fee ${tier.fee.formatExact()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit tier ${index + 1}',
              ),
              IconButton(
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
                tooltip: canRemove
                    ? 'Remove tier ${index + 1}'
                    : 'At least one tier is required',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierEditor extends StatefulWidget {
  const _TierEditor({required this.tier, required this.isLast});

  final GcashFeeTier tier;
  final bool isLast;

  @override
  State<_TierEditor> createState() => _TierEditorState();
}

class _TierEditorState extends State<_TierEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late final TextEditingController _feeController;
  late bool _isOpenEnded;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(text: _asInput(widget.tier.min));
    _maxController = TextEditingController(
      text: widget.tier.max == null ? '' : _asInput(widget.tier.max!),
    );
    _feeController = TextEditingController(text: _asInput(widget.tier.fee));
    _isOpenEnded = widget.tier.isOpenEnded;
  }

  static String _asInput(Money amount) =>
      (amount.centavos / Money.centavosPerPeso).toStringAsFixed(2);

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final min = Money.tryParse(_minController.text);
    final fee = Money.tryParse(_feeController.text);
    final max = _isOpenEnded ? null : Money.tryParse(_maxController.text);
    if (min == null || fee == null) return;
    if (!_isOpenEnded && max == null) return;

    Navigator.of(context).pop(GcashFeeTier(min: min, max: max, fee: fee));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Fee tier', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _minController,
                decoration: const InputDecoration(
                  labelText: 'Orders from (₱)',
                  prefixIcon: Icon(Icons.arrow_downward),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) => Validators.money(value, field: 'Minimum'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isOpenEnded,
                onChanged: (value) => setState(() => _isOpenEnded = value),
                title: const Text('No upper limit'),
                subtitle: const Text('The largest orders fall into this tier.'),
                contentPadding: EdgeInsets.zero,
              ),
              if (!_isOpenEnded)
                TextFormField(
                  controller: _maxController,
                  decoration: const InputDecoration(
                    labelText: 'Up to and including (₱)',
                    prefixIcon: Icon(Icons.arrow_upward),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => _isOpenEnded
                      ? null
                      : Validators.money(value, field: 'Maximum'),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _feeController,
                decoration: const InputDecoration(
                  labelText: 'Fee for this tier (₱)',
                  prefixIcon: Icon(Icons.payments_outlined),
                  helperText: 'Charged once for the whole order.',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) => Validators.money(value, field: 'Fee'),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _submit, child: const Text('Use it')),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
