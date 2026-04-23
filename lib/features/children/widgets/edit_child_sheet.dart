import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create-or-edit sheet for a child. When [child] is null we're adding;
/// otherwise we're editing that child — the title, action label, and
/// delete affordance flip accordingly. Teachers tap the avatar to set
/// or change the child's photo.
class EditChildSheet extends ConsumerStatefulWidget {
  const EditChildSheet({
    required this.groups,
    this.child,
    this.initialGroupId,
    super.key,
  });

  final List<Group> groups;

  /// When null, the sheet acts as "Add child".
  final Child? child;

  /// Only honored in create mode.
  final String? initialGroupId;

  @override
  ConsumerState<EditChildSheet> createState() => _EditChildSheetState();
}

class _EditChildSheetState extends ConsumerState<EditChildSheet> {
  late final _firstNameController =
      TextEditingController(text: widget.child?.firstName ?? '');
  late final _lastNameController =
      TextEditingController(text: widget.child?.lastName ?? '');
  late final _notesController =
      TextEditingController(text: widget.child?.notes ?? '');
  late final _parentNameController =
      TextEditingController(text: widget.child?.parentName ?? '');

  late String? _selectedGroupId = widget.child?.groupId ??
      widget.initialGroupId ??
      (widget.groups.isNotEmpty ? widget.groups.first.id : null);

  /// Local file path for the avatar. Starts at the existing value and
  /// flips to null when the teacher taps "Remove photo".
  late String? _avatarPath = widget.child?.avatarPath;

  /// Standing drop-off / pickup times stored as "HH:mm" strings.
  /// Null = no expected time (drop-in kids); a set value drives the
  /// lateness flag on Today.
  late String? _expectedArrival = widget.child?.expectedArrival;
  late String? _expectedPickup = widget.child?.expectedPickup;

  bool _submitting = false;

  bool get _isEdit => widget.child != null;
  bool get _isValid => _firstNameController.text.trim().isNotEmpty;

  bool get _hasChanges {
    final child = widget.child;
    if (child == null) return true;
    String? trimOrNull(String s) =>
        s.trim().isEmpty ? null : s.trim();
    if (_firstNameController.text.trim() != child.firstName) return true;
    if (trimOrNull(_lastNameController.text) != child.lastName) return true;
    if (_selectedGroupId != child.groupId) return true;
    if (trimOrNull(_parentNameController.text) != child.parentName) return true;
    if (trimOrNull(_notesController.text) != child.notes) return true;
    if (_avatarPath != child.avatarPath) return true;
    if (_expectedArrival != child.expectedArrival) return true;
    if (_expectedPickup != child.expectedPickup) return true;
    return false;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _notesController.dispose();
    _parentNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final repo = ref.read(childrenRepositoryProvider);
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final notes = _notesController.text.trim();

    final parentName = _parentNameController.text.trim();
    final existing = widget.child;
    if (existing == null) {
      await repo.addChild(
        firstName: firstName,
        lastName: lastName.isEmpty ? null : lastName,
        groupId: _selectedGroupId,
        notes: notes.isEmpty ? null : notes,
        avatarPath: _avatarPath,
        parentName: parentName.isEmpty ? null : parentName,
        expectedArrival: _expectedArrival,
        expectedPickup: _expectedPickup,
      );
    } else {
      await repo.updateChild(
        id: existing.id,
        firstName: firstName,
        lastName: lastName.isEmpty ? null : lastName,
        clearLastName: lastName.isEmpty && existing.lastName != null,
        groupId: _selectedGroupId,
        clearGroupId: _selectedGroupId == null && existing.groupId != null,
        notes: notes.isEmpty ? null : notes,
        clearNotes: notes.isEmpty && existing.notes != null,
        avatarPath: _avatarPath,
        clearAvatarPath:
            _avatarPath == null && existing.avatarPath != null,
        parentName: parentName.isEmpty ? null : parentName,
        clearParentName:
            parentName.isEmpty && existing.parentName != null,
        expectedArrival: _expectedArrival,
        clearExpectedArrival:
            _expectedArrival == null && existing.expectedArrival != null,
        expectedPickup: _expectedPickup,
        clearExpectedPickup:
            _expectedPickup == null && existing.expectedPickup != null,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.child;
    if (existing == null) return;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Remove ${existing.firstName}?',
      message:
          'Observations and tags stay — only this child record is '
          "removed. You'll get a 5-second window to undo.",
      onDelete: () => ref
          .read(childrenRepositoryProvider)
          .deleteChild(existing.id),
      undoLabel: '${existing.firstName} removed',
      onUndo: () => ref
          .read(childrenRepositoryProvider)
          .restoreChild(existing),
    );
    if (!confirmed || !mounted) return;
    // Pop the sheet AND the detail screen beneath it so the teacher
    // lands back on the Children list — otherwise they'd be stranded
    // on a "Child not found" page.
    navigator
      ..pop() // sheet
      ..pop(); // detail
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = _firstNameController.text.trim();
    final fallbackInitial =
        first.isNotEmpty ? first.characters.first.toUpperCase() : '?';

    return StickyActionSheet(
      title: _isEdit ? 'Edit child' : 'New child',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
            )
          : null,
      actionBar: AppButton.primary(
        onPressed: _isValid && (!_isEdit || _hasChanges) && !_submitting
            ? _submit
            : null,
        label: _isEdit ? 'Save changes' : 'Add child',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AvatarPicker(
              currentPath: _avatarPath,
              fallbackInitial: fallbackInitial,
              onChanged: (path) => setState(() => _avatarPath = path),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _firstNameController,
            label: 'First name',
            hint: 'e.g. Jordan',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _lastNameController,
            label: 'Last name (optional)',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Group', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Builder(
            builder: (_) {
              // Clamp to a live group id — orphan references fall
              // back to "Unassigned" instead of hitting the dropdown
              // "exactly one" assertion.
              final resolvedId = _selectedGroupId != null &&
                      widget.groups.any((g) => g.id == _selectedGroupId)
                  ? _selectedGroupId
                  : null;
              return DropdownButtonFormField<String?>(
                initialValue: resolvedId,
                items: [
                  const DropdownMenuItem<String?>(
                    child: Text('Unassigned'),
                  ),
                  for (final group in widget.groups)
                    DropdownMenuItem<String?>(
                      value: group.id,
                      child: Text(group.name),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedGroupId = value),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _parentNameController,
            label: 'Parent or guardian (optional)',
            hint: 'Name — pre-fills parent concern notes',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Daily schedule', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "Drop-off time lights up Today's late-arrivals flag. Leave "
            'blank for drop-in / flexible-schedule kids — they never '
            'trigger it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _TimeChipField(
                  label: 'Drop-off',
                  value: _expectedArrival,
                  onPick: () async {
                    final picked = await _pickTime(
                      context,
                      seed: _expectedArrival,
                      fallbackHour: 8,
                      fallbackMinute: 30,
                    );
                    if (picked == null) return;
                    setState(() => _expectedArrival = picked);
                  },
                  onClear: _expectedArrival == null
                      ? null
                      : () => setState(() => _expectedArrival = null),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _TimeChipField(
                  label: 'Pickup',
                  value: _expectedPickup,
                  onPick: () async {
                    final picked = await _pickTime(
                      context,
                      seed: _expectedPickup,
                      fallbackHour: 17,
                      fallbackMinute: 0,
                    );
                    if (picked == null) return;
                    setState(() => _expectedPickup = picked);
                  },
                  onClear: _expectedPickup == null
                      ? null
                      : () => setState(() => _expectedPickup = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            hint: 'Allergies, preferences, anything staff should know',
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  /// Opens a showTimePicker seeded with the existing value, falling
  /// back to the reasonable default ([fallbackHour], [fallbackMinute])
  /// when the field is empty — saves teachers from hunting back to 8am
  /// on a freshly opened pickup picker.
  Future<String?> _pickTime(
    BuildContext context, {
    required String? seed,
    required int fallbackHour,
    required int fallbackMinute,
  }) async {
    TimeOfDay initial;
    if (seed != null) {
      final parts = seed.split(':');
      initial = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } else {
      initial = TimeOfDay(hour: fallbackHour, minute: fallbackMinute);
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
  }
}

/// Label + tappable chip showing a stored HH:mm value or the
/// placeholder "Set" prompt. Includes a small × to clear. Used for
/// the standing drop-off / pickup fields on the child edit sheet;
/// broken out so both fields share the same look without one getting
/// visually heavier than the other.
class _TimeChipField extends StatelessWidget {
  const _TimeChipField({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final String? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = value == null ? 'Set' : _fmt12h(value!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    display,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: value == null
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                ),
                if (onClear != null)
                  InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmt12h(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h >= 12 ? 'PM' : 'AM';
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
  }
}
