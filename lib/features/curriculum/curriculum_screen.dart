import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
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

  /// Selected age for scaling. Defaults to 6 — middle of the
  /// elementary band — and clamped to 3..12 by the chip row.
  int _scaleAge = 6;

  @override
  Widget build(BuildContext context) {
    final themeAsync = ref.watch(themeByIdProvider(widget.themeId));
    final sequencesAsync =
        ref.watch(lessonSequencesForThemeProvider(widget.themeId));

    return Scaffold(
      appBar: AppBar(
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
            return const _EmptyState();
          }
          // Clamp the selected week — sequences may have shrunk
          // under us (delete from another screen).
          final selected = _selectedWeek.clamp(0, sequences.length - 1);
          final sequence = sequences[selected];
          final theme = themeAsync.value;
          final accent = _accentForTheme(context, theme);
          return Column(
            children: [
              _WeekStrip(
                sequences: sequences,
                selectedIndex: selected,
                accent: accent,
                onSelect: (i) => setState(() => _selectedWeek = i),
              ),
              const Divider(height: 1),
              _AgeScalingBar(
                enabled: _ageScalingOn,
                age: _scaleAge,
                onToggle: (v) => setState(() => _ageScalingOn = v),
                onAgeChanged: (a) => setState(() => _scaleAge = a),
              ),
              const Divider(height: 1),
              Expanded(
                child: _WeekDetail(
                  sequence: sequence,
                  weekNumber: selected + 1,
                  accent: accent,
                  ageScalingOn: _ageScalingOn,
                  scaleAge: _scaleAge,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Resolve the accent color: theme.colorHex if set, otherwise the
  /// app's primary. Hex parsing is forgiving — invalid strings
  /// fall back to primary.
  Color _accentForTheme(BuildContext context, ProgramTheme? theme) {
    final hex = theme?.colorHex;
    if (hex == null || hex.isEmpty) {
      return Theme.of(context).colorScheme.primary;
    }
    try {
      var clean = hex.replaceFirst('#', '');
      if (clean.length == 6) clean = 'FF$clean';
      return Color(int.parse(clean, radix: 16));
    } on FormatException {
      return Theme.of(context).colorScheme.primary;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              'No sequences yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add lesson sequences and tag them with this theme '
              'to see a multi-week arc here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal scroller of week chips at the top of the screen.
/// Each chip is "Wk N" with its label hint (the sequence name's
/// first segment) — taps swap the selected index. Renders the
/// theme's accent color on the active chip.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.sequences,
    required this.selectedIndex,
    required this.accent,
    required this.onSelect,
  });

  final List<LessonSequence> sequences;
  final int selectedIndex;
  final Color accent;
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

/// Toggle row for "Show age scaling" + age picker.
class _AgeScalingBar extends StatelessWidget {
  const _AgeScalingBar({
    required this.enabled,
    required this.age,
    required this.onToggle,
    required this.onAgeChanged,
  });

  final bool enabled;
  final int age;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onAgeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Switch.adaptive(
            value: enabled,
            onChanged: onToggle,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Age scaling',
            style: theme.textTheme.labelLarge,
          ),
          const Spacer(),
          if (enabled)
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
    required this.ageScalingOn,
    required this.scaleAge,
  });

  final LessonSequence sequence;
  final int weekNumber;
  final Color accent;
  final bool ageScalingOn;
  final int scaleAge;

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
            // Title strip: week number + sequence name.
            Text(
              'Week $weekNumber',
              style: theme.textTheme.labelMedium?.copyWith(
                color: accent,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
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
