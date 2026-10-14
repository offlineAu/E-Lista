import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A tappable expiry-date picker with a "Doesn't expire" escape hatch.
///
/// Shown expanded by default rather than collapsed behind an "add an expiry date" toggle —
/// a restock is the one realistic moment the owner has the delivery in hand to read a date
/// off it, so the field should be in front of them, not hidden.
class ExpiryDateField extends StatefulWidget {
  const ExpiryDateField({required this.onChanged, super.key});

  /// Called whenever the picked date or the "doesn't expire" switch changes. `null` means
  /// either nothing has been picked yet or "doesn't expire" is on — both save as no expiry.
  final ValueChanged<DateTime?> onChanged;

  @override
  State<ExpiryDateField> createState() => _ExpiryDateFieldState();
}

class _ExpiryDateFieldState extends State<ExpiryDateField> {
  DateTime? _date;
  bool _noExpiry = false;

  void _notify() => widget.onChanged(_noExpiry ? null : _date);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_noExpiry)
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Expiry date (optional)',
                prefixIcon: Icon(Icons.event_outlined),
              ),
              child: Text(
                _date == null ? 'Not set' : DateFormat.yMMMd().format(_date!),
                style: _date == null
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : theme.textTheme.bodyMedium,
              ),
            ),
          ),
        SwitchListTile(
          value: _noExpiry,
          onChanged: (value) {
            setState(() => _noExpiry = value);
            _notify();
          },
          title: const Text("Doesn't expire"),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
