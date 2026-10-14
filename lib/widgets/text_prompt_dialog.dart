import 'package:flutter/material.dart';

/// A simple dialog that asks for a single line of text.
///
/// Owns its [TextEditingController] for the entire life of the dialog. A controller created
/// in a function, handed to a dialog, then disposed the moment `showDialog` returns is
/// broken: the dialog's exit transition is still animating and still references it, so a
/// rebuild during the transition crashes. Keeping the controller in a `State` ties its
/// lifetime to the dialog route exactly, which is the pattern Flutter expects.
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    required this.title,
    required this.label,
    this.helperText,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.confirmLabel = 'OK',
    this.cancelLabel = 'Cancel',
    this.description,
    super.key,
  });

  final String title;
  final String label;
  final String? helperText;
  final String? description;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.description != null) ...[
              Text(widget.description!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _controller,
              autofocus: true,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.helperText,
              ),
              validator: widget.validator,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Shows a [TextPromptDialog] and returns the accepted text, or `null` if cancelled.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String? description,
  String? helperText,
  bool obscureText = false,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => TextPromptDialog(
      title: title,
      label: label,
      description: description,
      helperText: helperText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator ?? (_) => null,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}