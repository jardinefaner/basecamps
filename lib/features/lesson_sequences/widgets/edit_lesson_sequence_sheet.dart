import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create / edit a lesson sequence — the "week" of a curriculum.
/// Surfaces every authoring field so a teacher can hand-build a
/// multi-week arc from scratch (not just import a template):
///
///   * name + description (always)
///   * theme picker — which multi-week arc this week belongs to
///   * core question — the morning-meeting prompt
///   * phase — free-text grouping label ("ALL ABOUT ME"); the
///     curriculum view groups consecutive sequences with the
///     same phase under one phase header
///   * color hex — per-week accent override; falls back to the
///     theme color when blank
///   * engine notes — pedagogical commentary (visible behind a
///     toggle in the curriculum view)
///
/// `defaultThemeId` lets callers pre-select a theme — the
/// curriculum view's "+ Add week" button passes the current
/// theme so the new sequence lands in the right arc without
/// the user having to pick.
class EditLessonSequenceSheet extends ConsumerStatefulWidget {
  const EditLessonSequenceSheet({
    super.key,
    this.sequence,
    this.defaultThemeId,
  });

  /// Null → create. Non-null → edit.
  final LessonSequence? sequence;

  /// Pre-selected theme on a fresh create. Ignored on edit.
  final String? defaultThemeId;

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
  late final _coreQuestionController = TextEditingController(
    text: widget.sequence?.coreQuestion ?? '',
  );
  late final _phaseController = TextEditingController(
    text: widget.sequence?.phase ?? '',
  );
  late final _colorController = TextEditingController(
    text: widget.sequence?.colorHex ?? '',
  );
  late final _engineNotesController = TextEditingController(
    text: widget.sequence?.engineNotes ?? '',
  );

  late String? _themeId =
      widget.sequence?.themeId ?? widget.defaultThemeId;

  bool _submitting = false;

  bool get _isEdit => widget.sequence != null;
  bool get _isValid => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _coreQuestionController.dispose();
    _phaseController.dispose();
    _colorController.dispose();
    _engineNotesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final repo = ref.read(lessonSequencesRepositoryProvider);
    final name = _nameController.text.trim();
    final desc = _trimmedOrNull(_descController);
    final coreQuestion = _trimmedOrNull(_coreQuestionController);
    final phase = _trimmedOrNull(_phaseController);
    final colorHex = _trimmedOrNull(_colorController);
    final engineNotes = _trimmedOrNull(_engineNotesController);
    if (_isEdit) {
      await repo.updateSequence(
        id: widget.sequence!.id,
        name: name,
        description: Value(desc),
        themeId: Value(_themeId),
        coreQuestion: Value(coreQuestion),
        phase: Value(phase),
        colorHex: Value(colorHex),
        engineNotes: Value(engineNotes),
      );
    } else {
      await repo.addSequence(
        name: name,
        description: desc,
        themeId: _themeId,
        coreQuestion: coreQuestion,
        phase: phase,
        colorHex: colorHex,
        engineNotes: engineNotes,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String? _trimmedOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final themesAsync = ref.watch(themesProvider);
    final themes = themesAsync.asData?.value ?? const <ProgramTheme>[];
    return StickyActionSheet(
      title: _isEdit ? 'Edit week' : 'New week',
      actionBar: AppButton.primary(
        onPressed: _isValid && !_submitting
            ? () => runWithErrorReport(context, _submit)
            : null,
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
            hint: 'e.g. Week 1: My World Inside',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          // Theme picker. Only shown when there's at least one
          // theme to pick — fresh programs see a hint to make
          // one in the Themes section first.
          if (themes.isEmpty)
            _ThemeMissingHint()
          else
            DropdownButtonFormField<String?>(
              initialValue: _themeId,
              decoration: const InputDecoration(
                labelText: 'Theme (which arc this week belongs to)',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  child: Text('— Free-floating, not in a theme —'),
                ),
                for (final t in themes)
                  DropdownMenuItem<String?>(
                    value: t.id,
                    child: Text(t.name),
                  ),
              ],
              onChanged: (v) => setState(() => _themeId = v),
            ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _coreQuestionController,
            label: 'Core question (optional)',
            hint: 'e.g. What makes me, me?',
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _descController,
            label: 'Description (optional)',
            hint: 'What this week is about',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.lg),
          // The phase / color / engine-notes block is the
          // "advanced" half of the form. Putting them under an
          // ExpansionTile keeps the sheet short for the common
          // edit (rename / re-attach to theme) without hiding
          // the fields entirely.
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              children: [
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _phaseController,
                  label: 'Phase label (optional)',
                  hint: 'e.g. ALL ABOUT ME',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _colorController,
                  label: 'Accent color (hex, optional)',
                  hint: 'e.g. #ff6b6b',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _engineNotesController,
                  label: 'Engine notes (optional)',
                  hint: 'Pedagogical commentary for teachers',
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the user opens the new-week sheet but has no
/// themes yet. Themes are the parent container; without one,
/// the sequence has nowhere to live (it can be free-floating
/// but the curriculum view won't surface it). Keep the hint
/// short — the action is "go make a theme."
class _ThemeMissingHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No themes yet. Create one in Themes first '
              "(curriculum weeks live inside a theme's arc), "
              'or save this as a free-floating sequence.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
