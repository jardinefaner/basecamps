import 'package:basecamp/core/format/color.dart';
import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Read-only preview of a teacher's own curriculum, mirroring the
/// shape of the bundled-template preview. The live curriculum view
/// is for *authoring* — toggles, long-press menus, "+ Add ritual"
/// affordances, age-scaling switches. This is the reading view: a
/// teacher hands the tablet to a parent or a sub and walks the
/// curriculum without any of the editing chrome getting in the way.
///
/// Same visual language as `CurriculumTemplatePreviewScreen` so
/// teachers see "this is what my curriculum looks like, exactly the
/// way Different World looks." Differences:
///   * Header shows theme name + date range (the template's tagline /
///     summary / audience aren't authorable on user themes — those
///     intro fields are template-specific).
///   * Daily rituals render flat (no Mon-Fri grouping) — same fix
///     as the template preview, since user-authored daily rituals
///     are also typically parallel practices, not day-pinned events.
///     Items with a `dayOfWeek` are sorted by it; items without one
///     fall after.
///   * Milestones from the WeekArc are rendered as a list (the
///     authoring layer can carry several; the template format only
///     has one).
class UserCurriculumPreviewScreen extends ConsumerStatefulWidget {
  const UserCurriculumPreviewScreen({required this.themeId, super.key});

  final String themeId;

  @override
  ConsumerState<UserCurriculumPreviewScreen> createState() =>
      _UserCurriculumPreviewScreenState();
}

class _UserCurriculumPreviewScreenState
    extends ConsumerState<UserCurriculumPreviewScreen> {
  int _selectedWeek = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeAsync = ref.watch(themeByIdProvider(widget.themeId));
    final sequencesAsync =
        ref.watch(lessonSequencesForThemeProvider(widget.themeId));
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: themeAsync.when(
          data: (t) => Text(t?.name ?? 'Curriculum'),
          loading: () => const Text('Curriculum'),
          error: (_, _) => const Text('Curriculum'),
        ),
      ),
      body: sequencesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (sequences) {
          if (sequences.isEmpty) {
            return const _EmptyPreview();
          }
          final ordered = _orderByWeekNumber(sequences);
          final selected = _selectedWeek.clamp(0, ordered.length - 1);
          final activeSequence = ordered[selected];
          final accent = parseHex(themeAsync.value?.colorHex) ??
              theme.colorScheme.primary;
          final weekAccent =
              parseHex(activeSequence.colorHex) ?? accent;
          return SafeArea(
            top: false,
            child: Column(
              children: [
                _Header(
                  programTheme: themeAsync.value,
                  accent: accent,
                  totalWeeks: ordered.length,
                ),
                _WeekStrip(
                  sequences: ordered,
                  selectedIndex: selected,
                  fallbackAccent: accent,
                  onSelect: (i) => setState(() => _selectedWeek = i),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _WeekBody(
                    sequence: activeSequence,
                    weekNumber: selected + 1,
                    accent: weekAccent,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Top header — theme name (already in the AppBar, so we skip),
/// date range, and total-weeks count. Stands in for the template
/// preview's tagline + summary + audience block. Themes don't
/// carry those fields; the date range is the closest analogue.
class _Header extends StatelessWidget {
  const _Header({
    required this.programTheme,
    required this.accent,
    required this.totalWeeks,
  });

  final ProgramTheme? programTheme;
  final Color accent;
  final int totalWeeks;

  @override
  Widget build(BuildContext context) {
    final t = programTheme;
    if (t == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final range = formatDateRange(t.startDate, t.endDate);
    final notes = (t.notes ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$range · $totalWeeks ${totalWeeks == 1 ? 'week' : 'weeks'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              notes,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.sequences,
    required this.selectedIndex,
    required this.fallbackAccent,
    required this.onSelect,
  });

  final List<LessonSequence> sequences;
  final int selectedIndex;
  final Color fallbackAccent;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        itemCount: sequences.length,
        itemBuilder: (_, i) {
          final isSelected = i == selectedIndex;
          final tint =
              parseHex(sequences[i].colorHex) ?? fallbackAccent;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: Text('Week ${i + 1}'),
              selected: isSelected,
              selectedColor: tint.withValues(alpha: 0.22),
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                color: isSelected ? tint : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w700 : null,
              ),
              side: BorderSide(
                color: isSelected
                    ? tint.withValues(alpha: 0.6)
                    : theme.colorScheme.outlineVariant,
              ),
              onSelected: (_) => onSelect(i),
            ),
          );
        },
      ),
    );
  }
}

class _WeekBody extends ConsumerWidget {
  const _WeekBody({
    required this.sequence,
    required this.weekNumber,
    required this.accent,
  });

  final LessonSequence sequence;
  final int weekNumber;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final arcAsync = ref.watch(weekArcProvider(sequence.id));
    return arcAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (arc) {
        final phase = (sequence.phase ?? '').trim();
        final coreQuestion = (sequence.coreQuestion ?? '').trim();
        final description = (sequence.description ?? '').trim();
        final engineNotes = (sequence.engineNotes ?? '').trim();
        // Daily list = items pinned 1..5 sorted by day, then any
        // unscheduled (anytime-this-week) items appended.
        final dailyItems = <SequenceItemWithLibrary>[];
        for (var d = 1; d <= 5; d++) {
          final items = arc.dailyByWeekday[d];
          if (items != null) dailyItems.addAll(items);
        }
        dailyItems.addAll(arc.dailyUnscheduled);
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            if (phase.isNotEmpty)
              Text(
                phase.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              'Week $weekNumber: ${_stripWeekPrefix(sequence.name)}',
              style: theme.textTheme.titleLarge,
            ),
            if (coreQuestion.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _CoreQuestionCallout(
                question: coreQuestion,
                accent: accent,
              ),
            ],
            if (description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            if (dailyItems.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'DAILY RITUALS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < dailyItems.length; i++) ...[
                _RitualCard(entry: dailyItems[i]),
                if (i < dailyItems.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
            if (arc.milestones.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              for (final m in arc.milestones) ...[
                _MilestoneCard(entry: m, accent: accent),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
            if (engineNotes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _EngineNotesCard(notes: engineNotes),
            ],
          ],
        );
      },
    );
  }
}

class _CoreQuestionCallout extends StatelessWidget {
  const _CoreQuestionCallout({
    required this.question,
    required this.accent,
  });

  final String question;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.question_mark_rounded, size: 18, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              question,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RitualCard extends StatelessWidget {
  const _RitualCard({required this.entry});

  final SequenceItemWithLibrary entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = entry.library;
    final summary = (lib.summary ?? '').trim();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lib.title, style: theme.textTheme.titleSmall),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.entry, required this.accent});

  final SequenceItemWithLibrary entry;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = entry.library;
    final summary = (lib.summary ?? '').trim();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'WEEKLY MILESTONE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(lib.title, style: theme.textTheme.titleSmall),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EngineNotesCard extends StatelessWidget {
  const _EngineNotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notes_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'ENGINE NOTES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            notes,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nothing to preview yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add a week from the curriculum view first.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Same week-number-aware sort the curriculum-today resolver uses.
/// Duplicated rather than imported to keep this preview file
/// self-contained (it has no other dependency on the resolver).
List<LessonSequence> _orderByWeekNumber(List<LessonSequence> rows) {
  return [...rows]
    ..sort((a, b) {
      final na = _weekNumber(a.name);
      final nb = _weekNumber(b.name);
      if (na != null && nb != null) return na.compareTo(nb);
      if (na != null) return -1;
      if (nb != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
}

int? _weekNumber(String name) {
  final match = RegExp(r'^\s*week\s+(\d+)', caseSensitive: false)
      .firstMatch(name);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

/// Same prefix-stripper used by the Today curriculum strip — turns
/// "Week 1: My World Inside" into "My World Inside" so the preview's
/// week header doesn't say "Week 1: Week 1: …".
String _stripWeekPrefix(String name) {
  final match =
      RegExp(r'^\s*week\s+\d+\s*[:\-–]\s*', caseSensitive: false)
          .firstMatch(name);
  if (match == null) return name;
  return name.substring(match.end);
}
