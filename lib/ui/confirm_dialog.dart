import 'package:flutter/material.dart';

/// App-wide confirmation dialog. Every "are you sure?" moment in the
/// app should route through this helper so the layout, button order,
/// copy casing, and destructive styling stay consistent.
///
/// Defaults are destructive (most confirmations in the app are).
/// Set [destructive] to `false` for neutral confirmations (e.g. a
/// "Keep editing / Discard" wizard exit) so the primary action picks
/// up the regular theme color instead of the error tint.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
  return result ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = destructive
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onPrimaryContainer;
    final primaryBg = destructive
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.primaryContainer;

    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: primaryBg,
            foregroundColor: onPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
