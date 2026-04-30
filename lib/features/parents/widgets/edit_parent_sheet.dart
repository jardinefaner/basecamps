import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/save_action.dart';
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
  const EditParentSheet({
    super.key,
    this.parent,
    this.prefillFirstName,
    this.prefillLastName,
  });

  final Parent? parent;

  /// Seed values for a fresh create. Used to promote legacy free-text
  /// `Children.parentName` into a real Parent row without the teacher
  /// retyping — the child detail screen reads the parse, passes the
  /// first / last here, and the create flow opens already filled.
  /// Ignored on edit (widget.parent != null).
  final String? prefillFirstName;
  final String? prefillLastName;

  @override
  ConsumerState<EditParentSheet> createState() => _EditParentSheetState();
}

class _EditParentSheetState extends ConsumerState<EditParentSheet> {
  late final _firstController = TextEditingController(
    text: widget.parent?.firstName ?? widget.prefillFirstName ?? '',
  );
  late final _lastController = TextEditingController(
    text: widget.parent?.lastName ?? widget.prefillLastName ?? '',
  );
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
        onPressed: _isValid && !_submitting
            ? () => runWithErrorReport(context, _submit)
            : null,
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
          if (_isEdit) ...[
            const SizedBox(height: AppSpacing.xl),
            _StaffLinkSection(parentId: widget.parent!.id),
          ],
        ],
      ),
    );
  }
}

/// "Link to staff record" section — mirror of the staff↔parent bridge
/// rendered on the adult edit sheet. Since the FK is one-directional
/// (`adults.parent_id → parents.id`) this side is just a reverse
/// lookup: which adult (if any) claims this parent? On X-tap we clear
/// that adult's `parent_id` so the link drops.
///
/// Only rendered when editing an existing parent — a fresh create
/// has no id yet and can't be the target of a link.
class _StaffLinkSection extends ConsumerWidget {
  const _StaffLinkSection({required this.parentId});

  final String parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final linked = ref.watch(adultLinkedToParentProvider(parentId)).asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Link to staff record', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Shown when this parent is also on staff. Manage the link '
          "from the staff member's row — changes there appear here "
          'automatically.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (linked == null)
          Text(
            'Not linked. Open this person on the Adults tab and tap '
            '"Link parent record" to pair them.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              avatar: const Icon(Icons.badge_outlined, size: 16),
              label: Text(linked.name),
              onDeleted: () => _unlink(context, ref, linked),
              deleteIcon: const Icon(Icons.close, size: 16),
              deleteButtonTooltipMessage: 'Unlink staff',
              backgroundColor: theme.colorScheme.secondaryContainer,
            ),
          ),
      ],
    );
  }

  /// Clears the adult's `parent_id` via updateAdult. The chip drops
  /// immediately because `adultLinkedToParentProvider` re-queries on
  /// the write.
  Future<void> _unlink(
    BuildContext context,
    WidgetRef ref,
    Adult adult,
  ) async {
    await ref.read(adultsRepositoryProvider).updateAdult(
          id: adult.id,
          name: adult.name,
          role: adult.role,
          notes: adult.notes,
          // Avatar is untouched by an unlink — omitting `avatarFile`
          // and `clearAvatarPath` leaves the existing photo alone.
          parentId: const Value(null),
        );
  }
}
