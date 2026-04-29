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
///
/// Reduced to one visible field — **Title** — for the canonical
/// authoring path. On create, the saved sequence's name auto-prepends
/// "Week N: " where N is the next slot in the theme; on edit, the
/// existing prefix (if any) is stripped for display so the teacher
/// edits just the human title and the prefix re-attaches on save.
///
/// Description is offered as a second visible field but optional; it
/// landed below the title in the previous form too. The bigger change
/// is in what's gone:
///   * **Color override (per-week tint) — removed.** Theme color
///     flows through. The 10-week-each-tinted-differently usecase
///     is template-author territory; users authoring their own
///     curricula don't need it.
///   * **Core question, phase, engine notes — moved to Advanced.**
///     These were labeled prompts on the primary form, implying
///     every week needs them. In practice ~nobody fills them on
///     hand-authored weeks; templates can still populate them.
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
  /// Editor field carries the *human title only* — the "Week N: "
  /// prefix lives on the row's `name` column but isn't shown in the
  /// form. On create we prepend it; on edit we strip it for display
  /// and re-attach the same N (or the existing prefix) on save.
  late final _titleController = TextEditingController(
    text: _stripWeekPrefix(widget.sequence?.name ?? ''),
  );
  late final _descController =
      TextEditingController(text: widget.sequence?.description ?? '');
  late final _coreQuestionController = TextEditingController(
    text: widget.sequence?.coreQuestion ?? '',
  );
  late final _phaseController = TextEditingController(
    text: widget.sequence?.phase ?? '',
  );
  late final _engineNotesController = TextEditingController(
    text: widget.sequence?.engineNotes ?? '',
  );

  late String? _themeId =
      widget.sequence?.themeId ?? widget.defaultThemeId;

  bool _submitting = false;

  bool get _isEdit => widget.sequence != null;
  bool get _isValid => _titleController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _coreQuestionController.dispose();
    _phaseController.dispose();
    _engineNotesController.dispose();
    super.dispose();
  }

  /// Compose the row's `name` from the editor's title + a "Week N: "
  /// prefix. On edit we preserve whatever prefix the row already
  /// carried; on create we compute N from the count of sequences
  /// already attached to the theme. Falls back to no prefix when
  /// the theme has no sequences yet (first week — N is 1).
  String _composedName(String title, List<LessonSequence> siblings) {
    final clean = title.trim();
    if (clean.isEmpty) return '';
    if (_isEdit) {
      // Keep the existing prefix on the row to avoid renumbering
      // weeks unexpectedly. If there's no prefix on the original
      // name, save just the title.
      final originalPrefix = _extractWeekPrefix(widget.sequence!.name);
      return originalPrefix.isEmpty ? clean : '$originalPrefix$clean';
    }
    // Fresh create — count siblings (in this theme) and pick the
    // next slot. siblings already excludes us since we haven't
    // saved yet.
    final n = siblings.length + 1;
    return 'Week $n: $clean';
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final repo = ref.read(lessonSequencesRepositoryProvider);
    String? trim(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    final desc = trim(_descController);
    final coreQuestion = trim(_coreQuestionController);
    final phase = trim(_phaseController);
    final engineNotes = trim(_engineNotesController);
    // Pull siblings for week-number derivation. Safe to read once
    // synchronously; the curriculum view that opened this sheet
    // already watches the same provider.
    final siblings = _themeId == null
        ? const <LessonSequence>[]
        : ref.read(lessonSequencesForThemeProvider(_themeId!)).asData?.value ??
            const <LessonSequence>[];
    final composedName = _composedName(_titleController.text, siblings);

    if (_isEdit) {
      await repo.updateSequence(
        id: widget.sequence!.id,
        name: composedName,
        description: Value(desc),
        themeId: Value(_themeId),
        coreQuestion: Value(coreQuestion),
        phase: Value(phase),
        // Color override is no longer authorable — explicitly clear
        // any value the row carried so deselected sequences don't
        // inherit a stale tint. (For brand-new rows the column is
        // null by default.)
        colorHex: const Value(null),
        engineNotes: Value(engineNotes),
      );
    } else {
      await repo.addSequence(
        name: composedName,
        description: desc,
        themeId: _themeId,
        coreQuestion: coreQuestion,
        phase: phase,
        engineNotes: engineNotes,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
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
            controller: _titleController,
            label: 'Title',
            hint: 'e.g. Wake Up the Senses',
            onChanged: (_) => setState(() {}),
          ),
          if (!_isEdit)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Builder(
                builder: (context) {
                  final theme = Theme.of(context);
                  final siblings = _themeId == null
                      ? const <LessonSequence>[]
                      : ref
                              .watch(lessonSequencesForThemeProvider(_themeId!))
                              .asData?.value ??
                          const <LessonSequence>[];
                  final n = siblings.length + 1;
                  return Text(
                    'Will save as "Week $n: …"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _descController,
            label: 'Description (optional)',
            hint: 'What this week is about, in a sentence or two.',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.md),
          // Theme picker. Only shown when there's at least one
          // theme to pick — fresh programs see a hint to make one
          // in Themes first. (Most callers pre-attach via
          // `defaultThemeId`, so this is mainly load-bearing for
          // the rare standalone-create case.)
          if (themes.isEmpty)
            _ThemeMissingHint()
          else
            DropdownButtonFormField<String?>(
              initialValue: _themeId,
              decoration: const InputDecoration(
                labelText: 'Theme',
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
          const SizedBox(height: AppSpacing.lg),
          // The advanced expander holds the three template-author
          // fields: core question, phase, engine notes. Most weeks
          // don't carry any of them, so collapsing keeps the form
          // a one-prompt affair for the common case.
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
                  controller: _coreQuestionController,
                  label: 'Core question (optional)',
                  hint: 'e.g. What makes me, me?',
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _phaseController,
                  label: 'Phase label (optional)',
                  hint: 'e.g. ALL ABOUT ME',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _engineNotesController,
                  label: 'Engine notes (optional)',
                  hint: 'Pedagogical commentary for teachers.',
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

/// Shown when the user opens the new-week sheet but has no themes
/// yet. Themes are the parent container; without one, the sequence
/// has nowhere to live (it can be free-floating but the curriculum
/// view won't surface it).
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

/// Strip a leading "Week N:" / "Week N -" / "Week N –" prefix.
/// Lets the editor's title field display the human title only,
/// even when the row's `name` column carries the full composed
/// "Week 1: Wake Up the Senses". Tolerant of missing prefix —
/// returns the original string when no match.
String _stripWeekPrefix(String name) {
  final match =
      RegExp(r'^\s*week\s+\d+\s*[:\-–]\s*', caseSensitive: false)
          .firstMatch(name);
  if (match == null) return name;
  return name.substring(match.end);
}

/// Inverse of [_stripWeekPrefix] — returns the prefix portion
/// (including its trailing separator + space), or empty when the
/// name carries none. Used on save to preserve whatever convention
/// the existing row was using rather than renumbering it.
String _extractWeekPrefix(String name) {
  final match =
      RegExp(r'^\s*week\s+\d+\s*[:\-–]\s*', caseSensitive: false)
          .firstMatch(name);
  if (match == null) return '';
  return name.substring(0, match.end);
}
