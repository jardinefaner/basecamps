import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create / edit a lesson sequence — just name + optional description.
/// The ordered list of items lives on the detail screen so this sheet
/// stays fast to open for the common "rename it" edit.
class EditLessonSequenceSheet extends ConsumerStatefulWidget {
  const EditLessonSequenceSheet({super.key, this.sequence});

  /// Null → create. Non-null → edit.
  final LessonSequence? sequence;

  @override
  ConsumerState<EditLessonSequenceSheet> createState() =>
      _EditLessonSequenceSheetState();
}

class _EditLessonSequenceSheetState
    extends ConsumerState<EditLessonSequenceSheet> {
  late final _nameController =
      TextEditingController(text: widget.sequence?.name ?? '');
  late final _descController =
      TextEditingController(text: widget.sequence?.description ?? '');
  bool _submitting = false;

  bool get _isEdit => widget.sequence != null;
  bool get _isValid => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final repo = ref.read(lessonSequencesRepositoryProvider);
    final name = _nameController.text.trim();
    final desc = _descController.text.trim().isEmpty
        ? null
        : _descController.text.trim();
    if (_isEdit) {
      await repo.updateSequence(
        id: widget.sequence!.id,
        name: name,
        description: Value(desc),
      );
    } else {
      await repo.addSequence(name: name, description: desc);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StickyActionSheet(
      title: _isEdit ? 'Edit sequence' : 'New sequence',
      actionBar: AppButton.primary(
        onPressed: _isValid && !_submitting ? _submit : null,
        label: _isEdit ? 'Save' : 'Create',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Name',
            hint: 'e.g. Bug Week · Kindness lessons',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _descController,
            label: 'Description (optional)',
            hint: 'What this sequence is for',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
