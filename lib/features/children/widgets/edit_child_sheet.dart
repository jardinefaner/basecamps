import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
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
    this.initialPodId,
    super.key,
  });

  final List<Group> groups;

  /// When null, the sheet acts as "Add child".
  final Child? child;

  /// Only honored in create mode.
  final String? initialPodId;

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
      widget.initialPodId ??
      (widget.groups.isNotEmpty ? widget.groups.first.id : null);

  /// Local file path for the avatar. Starts at the existing value and
  /// flips to null when the teacher taps "Remove photo".
  late String? _avatarPath = widget.child?.avatarPath;

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
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.child;
    if (existing == null) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove ${existing.firstName}?',
      message:
          'Observations and tags stay — only this child record is removed.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await ref.read(childrenRepositoryProvider).deleteChild(existing.id);
    if (!mounted) return;
    Navigator.of(context).pop();
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
          DropdownButtonFormField<String?>(
            initialValue: _selectedGroupId,
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
            onChanged: (value) => setState(() => _selectedGroupId = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _parentNameController,
            label: 'Parent or guardian (optional)',
            hint: 'Name — pre-fills parent concern notes',
            onChanged: (_) => setState(() {}),
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
}
