import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/lesson_sequences/widgets/edit_lesson_sequence_sheet.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:basecamp/theme/spacing.dart';
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

  /// "Show age scaling" toggle. Off by default so the screen opens
  /// with the canonical (unscaled) text — the teacher opts in when
  /// they want to see how the activity reads for a different age.
  bool _ageScalingOn = false;

  /// "Show engine notes" toggle. Off by default — the engine
  /// commentary is curriculum-author-facing, not learner-facing.
  /// Surfaces the per-week pedagogical notes (`engine_notes`)
  /// behind the same toggle row as age scaling.
  bool _engineOn = false;

  /// Selected age for scaling. Defaults to 6 — middle of the
  /// elementary band — and clamped to 3..12 by the chip row.
  int _scaleAge = 6;

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
          final accent = _parseHex(sequence.colorHex) ??
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
                ageEnabled: _ageScalingOn,
                age: _scaleAge,
                engineEnabled: _engineOn,
                onAgeToggle: (v) => setState(() => _ageScalingOn = v),
                onAgeChanged: (a) => setState(() => _scaleAge = a),
                onEngineToggle: (v) => setState(() => _engineOn = v),
              ),
              const Divider(height: 1),
              Expanded(
                child: _WeekDetail(
                  sequence: sequence,
                  weekNumber: selected + 1,
                  accent: accent,
                  ageScalingOn: _ageScalingOn,
                  scaleAge: _scaleAge,
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
  /// app's primary. Delegates the hex parsing to the file-level
  /// [_parseHex] so per-week colors share the same logic.
  Color _accentForTheme(BuildContext context, ProgramTheme? theme) {
    return _parseHex(theme?.colorHex) ??
        Theme.of(context).colorScheme.primary;
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
            color: _parseHex(s.colorHex) ?? Colors.grey,
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
            color: _parseHex(seqs[i].colorHex) ?? Colors.grey,
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
              _parseHex(sequences[i].colorHex) ?? fallbackAccent;
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
class _ToggleBar extends StatelessWidget {
  const _ToggleBar({
    required this.ageEnabled,
    required this.age,
    required this.engineEnabled,
    required this.onAgeToggle,
    required this.onAgeChanged,
    required this.onEngineToggle,
  });

  final bool ageEnabled;
  final int age;
  final bool engineEnabled;
  final ValueChanged<bool> onAgeToggle;
  final ValueChanged<int> onAgeChanged;
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
          FilterChip(
            label: const Text('Age scaling'),
            selected: ageEnabled,
            onSelected: onAgeToggle,
          ),
          if (ageEnabled) ...[
            const SizedBox(width: AppSpacing.sm),
            DropdownButton<int>(
              value: age,
              underline: const SizedBox.shrink(),
              items: [
                for (int a = 3; a <= 12; a++)
                  DropdownMenuItem(value: a, child: Text('Age $a')),
              ],
              onChanged: (v) {
                if (v != null) onAgeChanged(v);
              },
            ),
          ],
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

/// Forgiving hex parser. Returns null on malformed input so the
/// caller can fall back to a default. Accepts `#rrggbb` and
/// `rrggbb`; longer / shorter strings are rejected.
Color? _parseHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    var clean = hex.replaceFirst('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    if (clean.length != 8) return null;
    return Color(int.parse(clean, radix: 16));
  } on FormatException {
    return null;
  }
}

/// Body of the screen: title, core question, daily list, milestone.
/// Subscribes to the WeekArc projection for [sequence].
class _WeekDetail extends ConsumerWidget {
  const _WeekDetail({
    required this.sequence,
    required this.weekNumber,
    required this.accent,
    required this.ageScalingOn,
    required this.scaleAge,
    required this.engineOn,
    required this.onEditWeek,
  });

  final bool engineOn;
  final LessonSequence sequence;
  final int weekNumber;
  final Color accent;
  final bool ageScalingOn;
  final int scaleAge;
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
            Text(
              'Daily rituals',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),

            // Mon..Fri columns. We always render the 5 weekday
            // slots — even empty ones — so the teacher sees the
            // full skeleton of the week and can spot a gap.
            for (int day = 1; day <= 5; day++)
              _DayBlock(
                weekday: day,
                items: arc.dailyByWeekday[day] ?? const [],
                ageScalingOn: ageScalingOn,
                scaleAge: scaleAge,
              ),

            if (arc.dailyUnscheduled.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _DayBlock(
                weekday: null,
                items: arc.dailyUnscheduled,
                ageScalingOn: ageScalingOn,
                scaleAge: scaleAge,
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            // Milestone block — the weekly capstone share-out.
            _MilestoneSection(
              items: arc.milestones,
              accent: accent,
              ageScalingOn: ageScalingOn,
              scaleAge: scaleAge,
            ),
          ],
        );
      },
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

class _DayBlock extends StatelessWidget {
  const _DayBlock({
    required this.weekday,
    required this.items,
    required this.ageScalingOn,
    required this.scaleAge,
  });

  /// 1..5 (Mon..Fri) or null for the "Anytime this week" bucket.
  final int? weekday;
  final List<SequenceItemWithLibrary> items;
  final bool ageScalingOn;
  final int scaleAge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = weekday == null ? 'Anytime' : _weekdayName(weekday!);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed-width day label so the body cards line up.
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Text(
                      '—',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final entry in items)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.sm,
                          ),
                          child: _ActivityCardTile(
                            entry: entry,
                            ageScalingOn: ageScalingOn,
                            scaleAge: scaleAge,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _weekdayName(int day) {
    const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return day >= 1 && day <= 7 ? names[day] : 'Day $day';
  }
}

class _MilestoneSection extends StatelessWidget {
  const _MilestoneSection({
    required this.items,
    required this.accent,
    required this.ageScalingOn,
    required this.scaleAge,
  });

  final List<SequenceItemWithLibrary> items;
  final Color accent;
  final bool ageScalingOn;
  final int scaleAge;

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
            Text(
              'Weekly milestone',
              style: theme.textTheme.titleSmall,
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
                ageScalingOn: ageScalingOn,
                scaleAge: scaleAge,
                emphasized: true,
                accent: accent,
              ),
            ),
      ],
    );
  }
}

/// One card showing a library item — title, optional hook, and
/// either the scaled or unscaled summary depending on the toggle.
class _ActivityCardTile extends ConsumerWidget {
  const _ActivityCardTile({
    required this.entry,
    required this.ageScalingOn,
    required this.scaleAge,
    this.emphasized = false,
    this.accent,
  });

  final SequenceItemWithLibrary entry;
  final bool ageScalingOn;
  final int scaleAge;

  /// Milestone tiles get a gentle accent border so the eye lands
  /// on them after scanning the daily strip.
  final bool emphasized;
  final Color? accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(activityLibraryRepositoryProvider);
    final scaled = ageScalingOn
        ? repo.scaleForAge(entry.library, scaleAge)
        : null;

    final title = entry.library.title;
    final hook = scaled?.hook ?? entry.library.hook;
    final summary = scaled?.summary ?? entry.library.summary;
    final hasVariantForAge = scaled?.summary != null &&
        entry.library.summary != scaled!.summary;

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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (ageScalingOn)
                  _AgeScaledBadge(
                    hasVariant: hasVariantForAge,
                    age: scaleAge,
                  ),
              ],
            ),
            if (hook != null && hook.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                hook,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
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
    );
  }
}

class _AgeScaledBadge extends StatelessWidget {
  const _AgeScaledBadge({required this.hasVariant, required this.age});

  /// True when the card actually has a variant for [age] (vs falling
  /// back to the canonical text). The styling differs so the
  /// teacher can tell at a glance which cards are pre-authored vs
  /// borrowed.
  final bool hasVariant;
  final int age;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = hasVariant
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = hasVariant
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        hasVariant ? 'age $age' : 'age $age (default)',
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
