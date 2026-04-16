import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditSpecialistSheet extends ConsumerStatefulWidget {
  const EditSpecialistSheet({super.key, this.specialist});

  final Specialist? specialist;

  @override
  ConsumerState<EditSpecialistSheet> createState() =>
      _EditSpecialistSheetState();
}

class _EditSpecialistSheetState extends ConsumerState<EditSpecialistSheet> {
  late final _nameController =
      TextEditingController(text: widget.specialist?.name ?? '');
  late final _roleController =
      TextEditingController(text: widget.specialist?.role ?? '');
  late final _notesController =
      TextEditingController(text: widget.specialist?.notes ?? '');
  bool _submitting = false;

  bool get _isEdit => widget.specialist != null;
  bool get _isValid => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final repo = ref.read(specialistsRepositoryProvider);
    final name = _nameController.text.trim();
    final role =
        _roleController.text.trim().isEmpty ? null : _roleController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    if (_isEdit) {
      await repo.updateSpecialist(
        id: widget.specialist!.id,
        name: name,
        role: role,
        notes: notes,
      );
    } else {
      await repo.addSpecialist(name: name, role: role, notes: notes);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    await ref
        .read(specialistsRepositoryProvider)
        .deleteSpecialist(widget.specialist!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StickyActionSheet(
      title: _isEdit ? 'Edit specialist' : 'New specialist',
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
        onPressed: _isValid ? _submit : null,
        label: _isEdit ? 'Save' : 'Add specialist',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Name',
            hint: 'e.g. Sarah',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _roleController,
            label: 'Role (optional)',
            hint: 'e.g. Art teacher',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
