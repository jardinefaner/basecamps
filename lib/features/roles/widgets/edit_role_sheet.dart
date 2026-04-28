import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/roles/roles_repository.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Add / edit a role. Single required field (name). On create, the
/// sheet pops with the newly-created role id so callers (the adult
/// edit sheet's "+ New role" action chip) can immediately select it
/// — same contract as EditParentSheet.
class EditRoleSheet extends ConsumerStatefulWidget {
  const EditRoleSheet({super.key, this.role});

  /// Null → create. Non-null → edit.
  final Role? role;

  @override
  ConsumerState<EditRoleSheet> createState() => _EditRoleSheetState();
}

class _EditRoleSheetState extends ConsumerState<EditRoleSheet> {
  late final _nameController =
      TextEditingController(text: widget.role?.name ?? '');
  bool _submitting = false;

  bool get _isEdit => widget.role != null;
  bool get _isValid => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final repo = ref.read(rolesRepositoryProvider);
    final name = _nameController.text.trim();
    String? resultId;
    if (_isEdit) {
      await repo.updateRole(id: widget.role!.id, name: name);
      resultId = widget.role!.id;
    } else {
      resultId = await repo.addRole(name: name);
    }
    if (!mounted) return;
    Navigator.of(context).pop<String?>(resultId);
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final role = widget.role!;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete "${role.name}"?',
      message: 'Adults tagged with this role lose the link; their '
          'legacy job-title string (if any) stays as a display '
          "fallback. You'll get a 5-second window to undo.",
      onDelete: () =>
          ref.read(rolesRepositoryProvider).deleteRole(role.id),
      undoLabel: '"${role.name}" removed',
      onUndo: () =>
          ref.read(rolesRepositoryProvider).restoreRole(role),
    );
    if (!confirmed || !mounted) return;
    navigator.pop<String?>();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StickyActionSheet(
      title: _isEdit ? 'Edit role' : 'New role',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              tooltip: 'Delete role',
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
        label: _isEdit ? 'Save' : 'Add role',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Role name',
            hint: 'e.g. Art teacher · Director · Head cook',
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}
