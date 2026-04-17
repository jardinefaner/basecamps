import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create-or-edit sheet for a kid. When [kid] is null we're adding;
/// otherwise we're editing that kid — the title, action label, and
/// delete affordance flip accordingly. Teachers tap the avatar to set
/// or change the kid's photo.
class EditKidSheet extends ConsumerStatefulWidget {
  const EditKidSheet({
    required this.pods,
    this.kid,
    this.initialPodId,
    super.key,
  });

  final List<Pod> pods;

  /// When null, the sheet acts as "Add kid".
  final Kid? kid;

  /// Only honored in create mode.
  final String? initialPodId;

  @override
  ConsumerState<EditKidSheet> createState() => _EditKidSheetState();
}

class _EditKidSheetState extends ConsumerState<EditKidSheet> {
  late final _firstNameController =
      TextEditingController(text: widget.kid?.firstName ?? '');
  late final _lastNameController =
      TextEditingController(text: widget.kid?.lastName ?? '');
  late final _notesController =
      TextEditingController(text: widget.kid?.notes ?? '');
  late final _parentNameController =
      TextEditingController(text: widget.kid?.parentName ?? '');

  late String? _selectedPodId = widget.kid?.podId ??
      widget.initialPodId ??
      (widget.pods.isNotEmpty ? widget.pods.first.id : null);

  /// Local file path for the avatar. Starts at the existing value and
  /// flips to null when the teacher taps "Remove photo".
  late String? _avatarPath = widget.kid?.avatarPath;

  bool _submitting = false;

  bool get _isEdit => widget.kid != null;
  bool get _isValid => _firstNameController.text.trim().isNotEmpty;

  bool get _hasChanges {
    final kid = widget.kid;
    if (kid == null) return true;
    String? trimOrNull(String s) =>
        s.trim().isEmpty ? null : s.trim();
    if (_firstNameController.text.trim() != kid.firstName) return true;
    if (trimOrNull(_lastNameController.text) != kid.lastName) return true;
    if (_selectedPodId != kid.podId) return true;
    if (trimOrNull(_parentNameController.text) != kid.parentName) return true;
    if (trimOrNull(_notesController.text) != kid.notes) return true;
    if (_avatarPath != kid.avatarPath) return true;
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
    final repo = ref.read(kidsRepositoryProvider);
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final notes = _notesController.text.trim();

    final parentName = _parentNameController.text.trim();
    final existing = widget.kid;
    if (existing == null) {
      await repo.addKid(
        firstName: firstName,
        lastName: lastName.isEmpty ? null : lastName,
        podId: _selectedPodId,
        notes: notes.isEmpty ? null : notes,
        avatarPath: _avatarPath,
        parentName: parentName.isEmpty ? null : parentName,
      );
    } else {
      await repo.updateKid(
        id: existing.id,
        firstName: firstName,
        lastName: lastName.isEmpty ? null : lastName,
        clearLastName: lastName.isEmpty && existing.lastName != null,
        podId: _selectedPodId,
        clearPodId: _selectedPodId == null && existing.podId != null,
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
    final existing = widget.kid;
    if (existing == null) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove ${existing.firstName}?',
      message:
          'Observations and tags stay — only this kid record is removed.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await ref.read(kidsRepositoryProvider).deleteKid(existing.id);
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
      title: _isEdit ? 'Edit kid' : 'New kid',
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
        label: _isEdit ? 'Save changes' : 'Add kid',
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
          Text('Pod', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            initialValue: _selectedPodId,
            items: [
              const DropdownMenuItem<String?>(
                child: Text('Unassigned'),
              ),
              for (final pod in widget.pods)
                DropdownMenuItem<String?>(
                  value: pod.id,
                  child: Text(pod.name),
                ),
            ],
            onChanged: (value) => setState(() => _selectedPodId = value),
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
