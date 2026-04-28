import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Add / edit a room. Used for both paths since rooms are simple —
/// name, optional capacity + notes, optional "home room for a group."
/// No wizard needed; the fields fit in one sheet.
class EditRoomSheet extends ConsumerStatefulWidget {
  const EditRoomSheet({super.key, this.room});

  /// Null → create. Non-null → edit.
  final Room? room;

  @override
  ConsumerState<EditRoomSheet> createState() => _EditRoomSheetState();
}

class _EditRoomSheetState extends ConsumerState<EditRoomSheet> {
  late final _nameController = TextEditingController(text: widget.room?.name ?? '');
  late final _notesController =
      TextEditingController(text: widget.room?.notes ?? '');
  late final _capacityController = TextEditingController(
    text: widget.room?.capacity?.toString() ?? '',
  );
  late String? _defaultForGroupId = widget.room?.defaultForGroupId;
  bool _submitting = false;

  bool get _isEdit => widget.room != null;
  bool get _isValid => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  int? _parseCapacity() {
    final raw = _capacityController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final repo = ref.read(roomsRepositoryProvider);
    final name = _nameController.text.trim();
    final capacity = _parseCapacity();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    if (_isEdit) {
      await repo.updateRoom(
        id: widget.room!.id,
        name: name,
        capacity: Value(capacity),
        notes: Value(notes),
        defaultForGroupId: Value(_defaultForGroupId),
      );
    } else {
      await repo.addRoom(
        name: name,
        capacity: capacity,
        notes: notes,
        defaultForGroupId: _defaultForGroupId,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final room = widget.room!;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete "${room.name}"?',
      message: 'Activities that pointed at this room keep their '
          'free-form location string; the link just goes away. '
          "You'll get a 5-second window to undo.",
      onDelete: () =>
          ref.read(roomsRepositoryProvider).deleteRoom(room.id),
      undoLabel: '"${room.name}" removed',
      onUndo: () =>
          ref.read(roomsRepositoryProvider).restoreRoom(room),
    );
    if (!confirmed || !mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupsAsync = ref.watch(groupsProvider);

    return StickyActionSheet(
      title: _isEdit ? 'Edit room' : 'New room',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              tooltip: 'Delete room',
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
            )
          : null,
      actionBar: AppButton.primary(
        onPressed: _isValid && !_submitting
            ? () => runWithErrorReport(context, _submit)
            : null,
        label: _isEdit ? 'Save' : 'Add room',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Room name',
            hint: 'e.g. Main Room · Art Room · Playground',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _capacityController,
            label: 'Capacity (optional)',
            hint: 'Max headcount',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Home room for a group',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'When set, activities created for this group default to '
            'this room. Leave unselected for shared spaces (gym, '
            'playground).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          groupsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (groups) {
              if (groups.isEmpty) {
                return Text(
                  'No groups yet — add some in the Children tab first.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilterChip(
                    label: const Text('Shared / no default group'),
                    selected: _defaultForGroupId == null,
                    onSelected: (_) =>
                        setState(() => _defaultForGroupId = null),
                  ),
                  for (final g in groups)
                    FilterChip(
                      label: Text(g.name),
                      selected: _defaultForGroupId == g.id,
                      onSelected: (_) =>
                          setState(() => _defaultForGroupId = g.id),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            hint: 'Projector, piano, sink — whatever staff should know',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
