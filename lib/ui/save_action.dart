import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Best-effort clipboard write. Some platforms (Safari without a
/// recent user gesture, Firefox in private mode, certain enterprise-
/// managed browsers) reject Clipboard.setData with a
/// `PlatformException(copy_fail, ...)` even though everything else
/// is wired correctly. The exception used to bubble up through any
/// runWithErrorReport-wrapped flow and read as "Save failed" — even
/// when the actual save had already succeeded and the clipboard
/// copy was a courtesy. Returns true on success so callers can
/// adapt UX (e.g. "Copied!" snackbar vs. "Code shown — copy
/// manually" dialog) when the clipboard's unavailable.
Future<bool> tryCopyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } on Object catch (e) {
    debugPrint('Clipboard copy skipped: $e');
    return false;
  }
}
