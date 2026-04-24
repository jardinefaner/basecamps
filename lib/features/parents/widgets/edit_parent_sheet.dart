import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Add / edit a parent or guardian. First name required; everything
/// else optional so "name-only" rows are fine for programs that don't
/// capture phone/email yet.
///
/// Returns the parent's id on successful add — the caller can use
/// it to immediately link to a child without re-opening the picker
/// ("Add new parent…" flow in the child-detail screen).
class EditParentSheet extends ConsumerStatefulWidget {
  const EditParentSheet({super.key, this.parent});

  final Parent? parent;

  @override
  ConsumerState<EditParentSheet> createState() => _EditParentSheetState();
}

class _EditParentSheetState extends ConsumerState<EditParentSheet> {
  late final _firstController =
      TextEditingController(text: widget.parent?.firstName ?? '');
  late final _lastController =
      TextEditingController(text: widget.parent?.lastName ?? '');
  late final _relationshipController =
      TextEditingController(text: widget.parent?.relationship ?? '');
  late final _phoneController =
      TextEditingController(text: widget.parent?.phone ?? '');
  late final _emailController =
      TextEditingController(text: widget.parent?.email ?? '');
  late final _notesController =
      TextEditingController(text: widget.parent?.notes ?? '');
  bool _submitting = false;

  bool get _isEdit => widget.parent != null;
  bool get _isValid => _firstController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _firstController.dispose();
    _lastController.dispose();
    _relationshipController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _nullIfEmpty(String raw) =>
      raw.trim().isEmpty ? null : raw.trim();

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final repo = ref.read(parentsRepositoryProvider);
    final firstName = _firstController.text.trim();
    final lastName = _nullIfEmpty(_lastController.text);
    final relationship = _nullIfEmpty(_relationshipController.text);
    final phone = _nullIfEmpty(_phoneController.text);
    final email = _nullIfEmpty(_emailController.text);
    final notes = _nullIfEmpty(_notesController.text);
    String? resultId;
    if (_isEdit) {
      await repo.updateParent(
        id: widget.parent!.id,
        firstName: firstName,
        lastName: Value(lastName),
        relationship: Value(relationship),
        phone: Value(phone),
        email: Value(email),
        notes: Value(notes),
      );
      resultId = widget.parent!.id;
    } else {
      resultId = await repo.addParent(
        firstName: firstName,
        lastName: lastName,
        relationship: relationship,
        phone: phone,
        email: email,
        notes: notes,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop<String?>(resultId);
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final parent = widget.parent!;
    final navigator = Navigator.of(context);
    final repo = ref.read(parentsRepositoryProvider);
    // Snapshot join rows before delete so undo can restore linked
    // children in one step.
    final links = await repo.snapshotLinks(parent.id);
    if (!mounted) return;
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete "${_displayName(parent)}"?',
      message: 'Removes the parent row and every child link. Children '
          "aren't deleted — just unlinked. You'll get a 5-second "
          'window to undo, which also restores the links.',
      onDelete: () => repo.deleteParent(parent.id),
      undoLabel: '"${_displayName(parent)}" removed',
      onUndo: () => repo.restoreParent(parent, links),
    );
    if (!confirmed || !mounted) return;
    navigator.pop<String?>();
  }

  String _displayName(Parent p) {
    final last = p.lastName;
    return last == null || last.isEmpty
        ? p.firstName
        : '${p.firstName} $last';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StickyActionSheet(
      title: _isEdit ? 'Edit parent' : 'New parent',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              tooltip: 'Delete parent',
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
            )
          : null,
      actionBar: AppButton.primary(
        onPressed: _isValid && !_submitting ? _submit : null,
        label: _isEdit ? 'Save' : 'Add parent',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _firstController,
            label: 'First name',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _lastController,
            label: 'Last name (optional)',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _relationshipController,
            label: 'Relationship (optional)',
            hint: 'Mom · Dad · Grandmother · Guardian · Auntie',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _phoneController,
            label: 'Phone (optional)',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _emailController,
            label: 'Email (optional)',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            hint: 'Emergency contact notes, custody arrangements, etc.',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
