import 'package:flutter/material.dart';

/// Runs [action] and surfaces any thrown error via debugPrint + a
/// snackbar so a failed save never reads as "nothing happened."
///
/// Wrap any async save handler that's plumbed straight to a
/// button's `onPressed`. Without this every Edit sheet and ad-hoc
/// form has to repeat the same try/catch + ScaffoldMessenger dance,
/// and any one we forget becomes a silent-failure trap.
///
/// Example:
/// ```dart
/// AppButton.primary(
///   label: 'Save',
///   onPressed: () => runWithErrorReport(context, _submit),
/// )
/// ```
///
/// Convention is to keep `_submit` itself void-returning and
/// rethrow-by-default — this wrapper owns the user-facing error
/// reporting so callers stay focused on the happy path. The
/// shared `StepWizardScaffold` already calls this for its
/// onFinalAction, so wizards don't need to opt in twice.
Future<void> runWithErrorReport(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on Object catch (e, st) {
    debugPrint('Save action failed: $e\n$st');
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }
}
