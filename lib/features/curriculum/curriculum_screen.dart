import 'package:basecamp/core/format/color.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/widgets/edit_library_item_sheet.dart';
import 'package:basecamp/features/curriculum/user_curriculum_preview_screen.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/lesson_sequences/widgets/edit_lesson_sequence_sheet.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `/more/themes/:themeId/curriculum` — the multi-week arc view for
/// a theme. Mirrors the "Different World" mockup: a horizontal week
/// strip across the top, then the selected week's daily rituals
/// (Mon–Fri) and the weekly milestone, all rendered from the
/// existing LessonSequences + LessonSequenceItems + ActivityLibrary
/// tables. The "Show age scaling" toggle re-renders activity card
/// summaries through `ActivityLibraryRepository.scaleForAge`.
///
/// Data shape: each `LessonSequence` whose `themeId` matches the
/// route param is one "week" in the arc. Items inside the sequence
/// carry `dayOfWeek` (1..5 = Mon..Fri) for daily rituals or
/// `kind = 'milestone'` for the weekly capstone. Free-floating
/// daily items with no `dayOfWeek` are bucketed under "Anytime
/// this week" so legacy / partially-authored weeks still render.
class CurriculumScreen extends ConsumerStatefulWidget {
  const CurriculumScreen({required this.themeId, super.key});

  final String themeId;

  @override
  ConsumerState<CurriculumScreen> createState() => _CurriculumScreenState();
}

class _CurriculumScreenState extends ConsumerState<CurriculumScreen> {
  /// Index into the sequences-for-theme list. Resets to 0 when the
  /// theme changes; stays put otherwise so a swipe back / forward
  /// preserves which week the teacher was reading.
  int _selectedWeek = 0;

  /// "Show engine notes" toggle. Off by default — the engine
  /// commentary is curriculum-author-facing, not learner-facing.
  bool _engineOn = false;

  @override
  Widget build(BuildContext context) {
    final flutterTheme = Theme.of(context);
    final themeAsync = ref.watch(themeByIdProvider(widget.themeId));
    final sequencesAsync =
        ref.watch(lessonSequencesForThemeProvider(widget.themeId));

    return Scaffold(
      // Lock the scaffold + app-bar background to scaffoldBackgroundColor
      // so the system status bar area + the bar itself + the body all
      // share one color. Without this the AppBar uses the theme's
      // surface color and we get a visible seam at the top of the
      // safe area.
      backgroundColor: flutterTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: flutterTheme.scaffoldBackgroundColor,
        title: themeAsync.when(
          data: (t) => Text(t?.name ?? 'Curriculum'),
          loading: () => const Text('Curriculum'),
          error: (_, _) => const Text('Curriculum'),
        ),
        actions: [
          // "Preview" — opens a read-only walk-through of this
          // curriculum in the same shape as the bundled-template
          // preview. The view above is for *authoring* (toggles,
          // long-press menus, "+ Add" buttons everywhere); the
          // preview is the reading view a teacher hands to a parent
          // or a sub.
          IconButton(
            tooltip: 'Preview',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => _openPreview(context),
          ),
          // "+ Add week" — creates a new lesson sequence pre-
          // attached to this theme. Lands the user back here
          // after save with the new week selected.
          IconButton(
            tooltip: 'Add week',
            icon: const Icon(Icons.add),
            onPressed: () => _addWeek(context),
          ),
        ],
      ),
      body: sequencesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (sequences) {
          if (sequences.isEmpty) {
            return _EmptyState(onAddWeek: () => _addWeek(context));
          }
          // Clamp the selected week — sequences may have shrunk
          // under us (delete from another screen).
          final selected = _selectedWeek.clamp(0, sequences.length - 1);
          final sequence = sequences[selected];
          final theme = themeAsync.value;
          // Per-week color overrides theme color when set (v47).
          // Lets a 10-week arc tint each week individually
          // (e.g. red for week 1, orange-red for week 2) without
          // mutating the theme's accent.
          final accent = parseHex(sequence.colorHex) ??
              _accentForTheme(context, theme);
          return Column(
            children: [
              _PhaseStrip(sequences: sequences, selectedIndex: selected),
              _WeekStrip(
                sequences: sequences,
                selectedIndex: selected,
                fallbackAccent: _accentForTheme(context, theme),
                onSelect: (i) => setState(() => _selectedWeek = i),
              ),
              const Divider(height: 1),
              _ToggleBar(
                engineEnabled: _engineOn,
                onEngineToggle: (v) => setState(() => _engineOn = v),
              ),
              const Divider(height: 1),
              Expanded(
                child: _WeekDetail(
                  sequence: sequence,
                  weekNumber: selected + 1,
                  accent: accent,
                  engineOn: _engineOn,
                  onEditWeek: () => _editWeek(context, sequence),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Resolve the accent color: theme.colorHex if set, otherwise the
  /// app's primary. Delegates the hex parsing to the shared
  /// `parseHex` helper so per-week colors share the same logic.
  Color _accentForTheme(BuildContext context, ProgramTheme? theme) {
    return parseHex(theme?.colorHex) ??
        Theme.of(context).colorScheme.primary;
  }

  /// Push the read-only preview of this curriculum. Same shape as
  /// the bundled-template preview; renders from Drift rather than
  /// the const template structure.
  Future<void> _openPreview(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            UserCurriculumPreviewScreen(themeId: widget.themeId),
      ),
    );
  }

  /// Open the rich-sequence edit sheet pre-attached to this
  /// theme. After save we reload via the stream — no manual
  /// state poke needed.
  Future<void> _addWeek(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLessonSequenceSheet(
        defaultThemeId: widget.themeId,
      ),
    );
  }

  /// Edit the currently-selected week's metadata. Same sheet,
  /// passing `sequence:` so it reads as edit.
  Future<void> _editWeek(
    BuildContext context,
    LessonSequence sequence,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLessonSequenceSheet(sequence: sequence),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddWeek});

  final VoidCallback onAddWeek;

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
              Icons.menu_book_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No weeks yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add the first week of your curriculum, or import a '
              'bundled template from the Curriculum screen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAddWeek,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a week'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phase strip — colored bars across the top showing the 5 phases
/// of a multi-week arc (e.g. "ALL ABOUT ME" spans weeks 1–2).
/// Groups consecutive sequences with the same `phase` value into
/// one bar, tinted with the first sequence in that group's color.
/// Empty when no sequence in the theme has a phase set.
class _PhaseStrip extends StatelessWidget {
  const _PhaseStrip({
    required this.sequences,
    required this.selectedIndex,
  });

  final List<LessonSequence> sequences;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _groupByPhase(sequences);
    if (groups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          for (final g in groups)
            Expanded(
              flex: g.weekCount,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: g.color.withValues(alpha: 0.10),
                    border: Border(
                      top: BorderSide(color: g.color, width: 2),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'W${g.weekRange}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: g.color,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        g.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: g.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static List<_PhaseGroup> _groupByPhase(List<LessonSequence> seqs) {
    final out = <_PhaseGroup>[];
    for (final s in seqs) {
      final phase = s.phase;
      if (phase == null || phase.isEmpty) continue;
      if (out.isNotEmpty && out.last.label == phase) {
        out.last.endIndex = out.length;
        out[out.length - 1] = out.last.copyExtended();
      } else {
        out.add(
          _PhaseGroup(
            label: phase,
            color: parseHex(s.colorHex) ?? Colors.grey,
            startIndex: out.fold<int>(0, (a, g) => a + g.weekCount),
            endIndex: out.fold<int>(0, (a, g) => a + g.weekCount),
          ),
        );
      }
    }
    // We only used the running total above — recompute weekCount
    // off the actual sequence list using each phase's first/last
    // run of contiguous matches. Simpler: re-walk.
    out.clear();
    String? current;
    for (var i = 0; i < seqs.length; i++) {
      final phase = seqs[i].phase;
      if (phase == null || phase.isEmpty) continue;
      if (current == phase && out.isNotEmpty) {
        out.last.endIndex = i;
      } else {
        out.add(
          _PhaseGroup(
            label: phase,
            color: parseHex(seqs[i].colorHex) ?? Colors.grey,
            startIndex: i,
            endIndex: i,
          ),
        );
        current = phase;
      }
    }
    return out;
  }
}

class _PhaseGroup {
  _PhaseGroup({
    required this.label,
    required this.color,
    required this.startIndex,
    required this.endIndex,
  });

  final String label;
  final Color color;
  final int startIndex;
  int endIndex;

  int get weekCount => endIndex - startIndex + 1;
  String get weekRange => weekCount == 1
      ? '${startIndex + 1}'
      : '${startIndex + 1}-${endIndex + 1}';

  _PhaseGroup copyExtended() => _PhaseGroup(
        label: label,
        color: color,
        startIndex: startIndex,
        endIndex: endIndex + 1,
      );
}

/// Horizontal scroller of week chips at the top of the screen.
/// Each chip is "Wk N" with its label hint (the sequence name's
/// first segment) — taps swap the selected index. Each chip is
/// tinted with that week's `colorHex` (or the theme color when
/// the sequence has none).
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
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        itemCount: sequences.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final isSel = i == selectedIndex;
          final accent =
              parseHex(sequences[i].colorHex) ?? fallbackAccent;
          final fill = isSel ? accent : theme.colorScheme.surfaceContainerHigh;
          // Pick a readable foreground for the accent — bright accents
          // get black text, dim ones get white. Computing luminance
          // is cheap and avoids the teacher choosing a "nice teal"
          // that turns the chip label invisible.
          final fg = isSel
              ? (accent.computeLuminance() > 0.5
                  ? Colors.black87
                  : Colors.white)
              : theme.colorScheme.onSurfaceVariant;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSel ? accent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Wk ${i + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _shortLabel(sequences[i].name),
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Strip a leading "Week N: " prefix if the sequence name uses
  /// the convention — keeps the chip tight without needing a
  /// dedicated label column.
  static String _shortLabel(String name) {
    final stripped = name.replaceFirst(
      RegExp(r'^\s*(week|wk)\s*\d+\s*[:\-–]\s*', caseSensitive: false),
      '',
    );
    return stripped.isEmpty ? name : stripped;
  }
}

/// Two compact toggle chips — "Age scaling" (with age dropdown
/// when on) and "Engine notes" — sit on a single row above the
/// week body. Tapping a chip flips its state; the corresponding
/// content slot below the toggle bar appears or disappears.
/// Single-toggle bar — engine notes only, since the age-scaling
/// feature was retired. Kept as a Row for layout consistency.
class _ToggleBar extends StatelessWidget {
  const _ToggleBar({
    required this.engineEnabled,
    required this.onEngineToggle,
  });

  final bool engineEnabled;
  final ValueChanged<bool> onEngineToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Spacer(),
          FilterChip(
            label: const Text('Engine notes'),
            selected: engineEnabled,
            onSelected: onEngineToggle,
          ),
        ],
      ),
    );
  }
}


/// Body of the screen: title, core question, daily list, milestone.
/// Subscribes to the WeekArc projection for [sequence].
class _WeekDetail extends ConsumerWidget {
  const _WeekDetail({
    required this.sequence,
    required this.weekNumber,
    required this.accent,
    required this.engineOn,
    required this.onEditWeek,
  });

  final bool engineOn;
  final LessonSequence sequence;
  final int weekNumber;
  final Color accent;
  final VoidCallback onEditWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final arcAsync = ref.watch(weekArcProvider(sequence.id));

    return arcAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (arc) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            // Title strip: week number + sequence name + edit pen.
            Row(
              children: [
                Text(
                  'Week $weekNumber',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit week',
                  iconSize: 18,
                  onPressed: onEditWeek,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              sequence.name,
              style: theme.textTheme.headlineSmall,
            ),
            if (sequence.description != null &&
                sequence.description!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                sequence.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (sequence.coreQuestion != null &&
                sequence.coreQuestion!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _CoreQuestionCallout(
                question: sequence.coreQuestion!,
                accent: accent,
              ),
            ],
            if (engineOn &&
                sequence.engineNotes != null &&
                sequence.engineNotes!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _EngineNotesPanel(text: sequence.engineNotes!),
            ],
            const SizedBox(height: AppSpacing.xl),

            // Daily section header.
            //
            // Daily rituals are *parallel practices* — all of them
            // happen every day of the week. The previous Mon..Fri
            // column layout implied weekday-pinning ("Smell Walk
            // only on Mondays") which is the opposite of what
            // curricula like Different World prescribe ("Smell Walk
            // every day, naming a different smell each day"). The
            // model commits to parallel-daily: `dayOfWeek` is now
            // ordinal position (ritual #1, #2, …) used for stable
            // ordering only. Day-specific scheduling lives in the
            // Schedule, not here.
            Text(
              'Daily rituals',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'All rituals run every day of the week. Tap to edit; '
              'long-press for more.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Flat list — items pinned 1..5 sorted by their ordinal,
            // then any unscheduled (no-position-yet) items appended.
            _DailyRitualsList(arc: arc),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    _addRitual(context, ref, sequence.id, arc),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add ritual'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Milestone block — the weekly capstone share-out.
            _MilestoneSection(
              items: arc.milestones,
              accent: accent,
              onAddMilestone: () =>
                  _addMilestone(context, ref, sequence.id),
            ),
          ],
        );
      },
    );
  }

  /// Two-step "add ritual" flow:
  ///   1. Open the rich library-card editor with empty state.
  ///   2. On save, the sheet returns the new library item id.
  ///   3. Link the card into this sequence as a daily ritual at
  ///      the next ordinal position (existing daily count + 1).
  ///
  /// Position is stored in `dayOfWeek` for backward compatibility —
  /// the field used to mean "the weekday this happens" but now
  /// means "this is the Nth ritual." That keeps the schema stable
  /// while the UX shift lands.
  Future<void> _addRitual(
    BuildContext context,
    WidgetRef ref,
    String sequenceId,
    WeekArc arc,
  ) async {
    final newId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const EditLibraryItemSheet(),
    );
    if (newId == null || !context.mounted) return;
    final dailyCount = arc.dailyByWeekday.values
            .fold<int>(0, (acc, list) => acc + list.length) +
        arc.dailyUnscheduled.length;
    await ref.read(lessonSequencesRepositoryProvider).addItem(
          sequenceId: sequenceId,
          libraryItemId: newId,
          // Next ordinal position. Capped at 5 to fit the existing
          // 1..5 schema range; rituals beyond five fall into the
          // unscheduled bucket and still render in the flat list.
          dayOfWeek: dailyCount < 5 ? dailyCount + 1 : null,
        );
  }

  /// Same flow for the weekly milestone — `kind: 'milestone'`,
  /// no day-of-week (milestones span the whole week).
  Future<void> _addMilestone(
    BuildContext context,
    WidgetRef ref,
    String sequenceId,
  ) async {
    final newId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const EditLibraryItemSheet(),
    );
    if (newId == null || !context.mounted) return;
    await ref.read(lessonSequencesRepositoryProvider).addItem(
          sequenceId: sequenceId,
          libraryItemId: newId,
          kind: 'milestone',
        );
  }
}

class _CoreQuestionCallout extends StatelessWidget {
  const _CoreQuestionCallout({required this.question, required this.accent});

  final String question;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Essential question',
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            question,
            style: theme.textTheme.titleMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Under the hood" panel — surfaces the curriculum author's
/// pedagogical commentary (engine_notes) for the current week.
/// Hidden by default; shown when the user flips the "Engine
/// notes" toggle on the bar above. Visually muted so it doesn't
/// compete with the learner-facing daily list.
class _EngineNotesPanel extends StatelessWidget {
  const _EngineNotesPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'UNDER THE HOOD',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat list of daily ritual cards — replaces the old per-weekday
/// column layout. Items pinned 1..5 sort by their ordinal first;
/// any items with no ordinal (the legacy "anytime" bucket) fall
/// after them. Empty state renders a one-liner instead of a 5-row
/// scaffold of dashes.
class _DailyRitualsList extends StatelessWidget {
  const _DailyRitualsList({required this.arc});

  final WeekArc arc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = <SequenceItemWithLibrary>[];
    for (var d = 1; d <= 5; d++) {
      final items = arc.dailyByWeekday[d];
      if (items != null) ordered.addAll(items);
    }
    ordered.addAll(arc.dailyUnscheduled);
    if (ordered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          'No daily rituals yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ActivityCardTile(entry: entry),
          ),
      ],
    );
  }
}

// _DayBlock + _weekdayName removed in the parallel-daily refactor —
// daily rituals are no longer grouped by weekday in the authoring
// view. _DailyRitualsList above is the replacement.

class _MilestoneSection extends StatelessWidget {
  const _MilestoneSection({
    required this.items,
    required this.accent,
    required this.onAddMilestone,
  });

  final List<SequenceItemWithLibrary> items;
  final Color accent;
  final VoidCallback onAddMilestone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star_rounded, size: 20, color: accent),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Weekly milestone',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: onAddMilestone,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          Text(
            'No milestone set for this week.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final entry in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ActivityCardTile(
                entry: entry,
                emphasized: true,
                accent: accent,
              ),
            ),
      ],
    );
  }
}

/// One card showing a library item — title + description (the old
/// hook + age-scaling rendering came out alongside the broader
/// curriculum-form simplification). Tap → editor; long-press → menu.
class _ActivityCardTile extends ConsumerWidget {
  const _ActivityCardTile({
    required this.entry,
    this.emphasized = false,
    this.accent,
  });

  final SequenceItemWithLibrary entry;

  /// Milestone tiles get a gentle accent border so the eye lands
  /// on them after scanning the daily strip.
  final bool emphasized;
  final Color? accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final title = entry.library.title;
    final summary = entry.library.summary;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: emphasized
              ? (accent ?? theme.colorScheme.primary).withValues(alpha: 0.6)
              : Colors.transparent,
          width: emphasized ? 1.5 : 0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Tap opens the library card editor for this item — full
        // control over title / summary / age variants. Long-press
        // surfaces the timing-and-removal menu (slice C: change
        // weekday, swap to milestone, remove from week).
        onTap: () => _openCardEditor(context, ref),
        onLongPress: () => _openItemMenu(context, ref),
        child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                summary,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  /// Open the rich library-card editor on the linked card.
  /// Lets the user edit title / summary / age variants in
  /// place from the curriculum view.
  Future<void> _openCardEditor(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLibraryItemSheet(item: entry.library),
    );
  }

  /// Long-press menu — convert daily↔milestone, schedule the card
  /// onto an actual day, or unlink it from this week. The earlier
  /// "move to Mon/Tue/…/Fri/Anytime" options are gone since daily
  /// rituals are now parallel practices (no per-weekday slot to
  /// move to). `dayOfWeek` is still set internally as ordinal
  /// position, just no longer surfaced as a UX concept here.
  Future<void> _openItemMenu(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final item = entry.item;
    final action = await showModalBottomSheet<_ItemAction>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ItemActionMenu(item: item),
    );
    if (action == null || !context.mounted) return;
    final repo = ref.read(lessonSequencesRepositoryProvider);
    switch (action) {
      case _ItemAction.removeFromWeek:
        await repo.deleteItem(item.id);
      case _ItemAction.toMilestone:
        await repo.updateItemMetadata(
          id: item.id,
          kind: const Value('milestone'),
          dayOfWeek: const Value(null),
        );
      case _ItemAction.toDaily:
        await repo.updateItemMetadata(
          id: item.id,
          kind: const Value('daily'),
        );
      case _ItemAction.schedule:
        // Push the same wizard the activity-library "Schedule" button
        // pushes — pre-fills title, hook, default duration, etc. from
        // the linked library card. No weekday seed: parallel-daily
        // rituals run every day, so let the teacher pick the actual
        // weekdays to schedule on inside the wizard.
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => NewActivityWizardScreen(
              initialLibraryItem: entry.library,
            ),
          ),
        );
    }
  }
}

/// Bottom-sheet picker for quick edits on a sequence item's
/// timing without going through a full edit form.
enum _ItemAction {
  toMilestone,
  toDaily,
  /// Schedule from curriculum — opens the activity wizard pre-filled
  /// from this card. Mirror, not link: the curriculum item and the
  /// resulting schedule template are independent rows. Edits to one
  /// don't propagate to the other (intentional — curriculum is "what
  /// we want to do this week," schedule is "when we're actually
  /// doing it"; a teacher routinely tweaks one without meaning the
  /// other).
  schedule,
  removeFromWeek,
}

class _ItemActionMenu extends StatelessWidget {
  const _ItemActionMenu({required this.item});

  final LessonSequenceItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMilestone = item.kind == 'milestone';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type toggle — daily ritual vs. weekly milestone. Daily
            // rituals run every day of the week; the weekly
            // milestone is the Friday share-out / capstone. (The
            // earlier "move to Mon/Tue/…/Fri" chip row was retired
            // when daily rituals stopped being weekday-pinned.)
            Text(
              'Type',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                ChoiceChip(
                  label: const Text('Daily ritual'),
                  selected: !isMilestone,
                  onSelected: isMilestone
                      ? (_) => Navigator.of(context).pop(_ItemAction.toDaily)
                      : null,
                ),
                ChoiceChip(
                  label: const Text('Weekly milestone'),
                  selected: isMilestone,
                  onSelected: !isMilestone
                      ? (_) => Navigator.of(context)
                          .pop(_ItemAction.toMilestone)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: Icon(
                Icons.event_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Schedule this card'),
              subtitle: const Text(
                'Open the activity wizard pre-filled from this card.',
              ),
              onTap: () =>
                  Navigator.of(context).pop(_ItemAction.schedule),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: Icon(
                Icons.link_off,
                color: theme.colorScheme.error,
              ),
              title: const Text('Remove from this week'),
              subtitle: const Text(
                'Card stays in the library for reuse.',
              ),
              onTap: () =>
                  Navigator.of(context).pop(_ItemAction.removeFromWeek),
            ),
          ],
        ),
      ),
    );
  }
}

// _AgeScaledBadge removed — age scaling feature retired.
