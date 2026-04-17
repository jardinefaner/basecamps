import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// State-holder for a single-type bulk-selection flow. Mix into any
/// list screen's `State` / `ConsumerState` that wants long-press-to-
/// enter + tap-to-toggle semantics. The Observe tab's multi-select
/// is deliberately hand-rolled (two independent sets — observations
/// and attachments — side by side); every other screen in the app
/// has just one kind of row, so this mixin fits.
mixin BulkSelectionMixin<T extends StatefulWidget> on State<T> {
  final Set<String> _selectedIds = <String>{};

  Set<String> get selectedIds => _selectedIds;
  int get selectedCount => _selectedIds.length;
  bool get isSelecting => _selectedIds.isNotEmpty;
  bool isSelected(String id) => _selectedIds.contains(id);

  /// Toggle one row in or out of the selection set. Wraps `setState`
  /// so callers just forward an id through.
  void toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  /// Drop every current pick. No-op when already empty so cancel
  /// handlers can be bound unconditionally.
  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    setState(_selectedIds.clear);
  }
}

/// Shared AppBar the app uses any time a list screen enters
/// bulk-select mode. primaryContainer tint, X to cancel, count on
/// the title, trash icon on the right. Screens with additional
/// bulk actions (e.g. "move to pod") can pass them through the
/// [extraActions] slot.
PreferredSizeWidget buildSelectionAppBar({
  required BuildContext context,
  required int count,
  required VoidCallback onCancel,
  required VoidCallback onDelete,
  List<Widget> extraActions = const [],
}) {
  final theme = Theme.of(context);
  return AppBar(
    backgroundColor: theme.colorScheme.primaryContainer,
    foregroundColor: theme.colorScheme.onPrimaryContainer,
    leading: IconButton(
      tooltip: 'Cancel selection',
      icon: const Icon(Icons.close),
      onPressed: onCancel,
    ),
    title: Text('$count selected'),
    actions: [
      ...extraActions,
      IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
      const SizedBox(width: AppSpacing.xs),
    ],
  );
}
