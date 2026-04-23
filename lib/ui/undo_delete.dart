import 'dart:async';

import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';

/// Confirm + delete + "Undo" snackbar in one helper. Every delete in
/// the app routes through here so the pattern is consistent: every
/// destructive tap has a 5-second window to take it back.
///
/// The helper is deliberately thin and source-agnostic — the caller
/// passes two async closures:
///   - [onDelete] does the actual destructive work against the
///     repository.
///   - [onUndo] reverses it (typically re-inserting the row via a
///     `restoreX` method).
///
/// Callers stay on the hook for getting the snapshot right before
/// calling [onDelete] — but since the snapshot is usually the row
/// they already have in hand, that's a single extra line per site.
///
/// Known limitation: some Drift FKs are `KeyAction.cascade`, which
/// means deleting a parent wipes its children at the SQL level.
/// Undo re-inserts the parent only; cascaded children are lost.
/// Acceptable for the typical "wrong row" tap — the undo window is
/// meant for mistakes, not for true rollback. Sites that have
/// expensive cascades can opt in to snapshot-and-restore-joins when
/// the cost is warranted.
Future<bool> confirmDeleteWithUndo({
  required BuildContext context,
  required String title,
  required String message,
  required Future<void> Function() onDelete,
  required String undoLabel,
  required Future<void> Function() onUndo,
  String confirmLabel = 'Remove',
}) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
  );
  if (!confirmed) return false;
  if (!context.mounted) return false;

  // Capture messenger BEFORE the async delete + any navigator pops
  // the caller might do after we return — a teacher deleting from
  // a detail screen will pop, invalidating the local context.
  final messenger = ScaffoldMessenger.of(context);

  await onDelete();

  // Hide any pending snackbar first so the new undo SnackBar always
  // wins — otherwise the previous "saved" snackbar from an earlier
  // action could linger and block this one.
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(undoLabel),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Fire-and-forget — the user doesn't care about the
            // return, and blocking the snackbar's dispatch loop on
            // a DB write would be silly.
            unawaited(onUndo());
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  return true;
}
