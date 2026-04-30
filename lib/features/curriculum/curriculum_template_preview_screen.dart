import 'package:basecamp/core/format/color.dart';
import 'package:basecamp/features/curriculum/templates/curriculum_template.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';

/// Read-only preview of a curriculum template — the "what am I
/// actually getting?" view a teacher hits before tapping Import.
///
/// Mirrors the layout of the live curriculum view in spirit (week
/// strip up top, selected week's daily rituals + milestone below)
/// but renders from the static [CurriculumTemplate] structure rather
/// than from Drift rows. No edit affordances — this is browsing,
/// not authoring.
///
/// A sticky bottom "Use this template" CTA opens the import sheet
/// the templates tab used to push directly. The detour through the
/// preview is the whole point: the previous flow was tap-card →
/// import, with no way to see what you were committing to except by
/// reading the 4-line summary on the card.
///
/// Built as a callback-driven screen rather than a route so the
/// caller (curriculum hub's Templates tab) controls how the import
/// sheet is presented — keeps this screen ignorant of the templates
/// tab's stateful import flow.
class CurriculumTemplatePreviewScreen extends StatefulWidget {
  const CurriculumTemplatePreviewScreen({
    required this.template,
    required this.onUse,
    super.key,
  });

  final CurriculumTemplate template;

  /// Called when the teacher taps "Use this template." The preview
  /// pops itself first so the caller's import sheet doesn't end up
  /// stacked on top of the preview screen — by the time onUse runs,
  /// the navigator stack is back where the caller wants it.
  final VoidCallback onUse;

  @override
  State<CurriculumTemplatePreviewScreen> createState() =>
      _CurriculumTemplatePreviewScreenState();
}

class _CurriculumTemplatePreviewScreenState
    extends State<CurriculumTemplatePreviewScreen> {
  /// Selected week index (0-based). Persisted within the screen so
  /// scrolling around the week strip doesn't lose your place.
  int _selectedWeek = 0;

  CurriculumTemplate get template => widget.template;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = parseHex(template.themeColorHex) ??
        theme.colorScheme.primary;
    final weeks = [...template.weeks]..sort((a, b) => a.week.compareTo(b.week));
    final selected = _selectedWeek.clamp(0, weeks.length - 1);
    final week = weeks[selected];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text(template.name),
      ),
      // Sticky CTA at the bottom — leaves the body free to scroll
      // and keeps the import action one tap away no matter how deep
      // the teacher has scrolled into a week.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onUse();
              },
              icon: const Icon(Icons.add),
              label: const Text('Use this template'),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _Header(template: template, accent: accent),
            _WeekStrip(
              weeks: weeks,
              selectedIndex: selected,
              accent: accent,
              onSelect: (i) => setState(() => _selectedWeek = i),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  _WeekHeader(week: week, accent: accent),
                  const SizedBox(height: AppSpacing.lg),
                  _DailyList(week: week),
                  const SizedBox(height: AppSpacing.lg),
                  _MilestoneCard(milestone: week.milestone, accent: accent),
                  if (week.engineNotes.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _EngineNotesCard(notes: week.engineNotes),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-of-page intro: tagline + summary + audience pill. Mirrors what
/// teachers see on the Templates tab card so the preview confirms the
/// thing they tapped.
class _Header extends StatelessWidget {
  const _Header({required this.template, required this.accent});

  final CurriculumTemplate template;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text(
            template.tagline,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            template.summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
              template.audience,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal week chips — same shape as the live curriculum view's
/// week strip so the preview reads as "this is what your curriculum
/// will look like."
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.weeks,
    required this.selectedIndex,
    required this.accent,
    required this.onSelect,
  });

  final List<WeekTemplate> weeks;
  final int selectedIndex;
  final Color accent;
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
        itemCount: weeks.length,
        itemBuilder: (_, i) {
          final isSelected = i == selectedIndex;
          final week = weeks[i];
          final tint = parseHex(week.colorHex) ?? accent;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: Text('Week ${week.week}'),
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

/// Big "Week N: Title" header + phase chip + core question + week
/// description. Sets the frame before the daily-rituals list.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.week, required this.accent});

  final WeekTemplate week;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = parseHex(week.colorHex) ?? accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (week.phase.trim().isNotEmpty)
          Text(
            week.phase.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: tint,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        const SizedBox(height: 2),
        Text(
          'Week ${week.week}: ${week.title}',
          style: theme.textTheme.titleLarge,
        ),
        if (week.coreQuestion.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.question_mark_rounded,
                  size: 18,
                  color: tint,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    week.coreQuestion,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (week.description.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            week.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Daily rituals rendered as a flat list of cards. Why not Mon-Fri:
/// in curricula like Different World, "daily rituals" are *parallel
/// daily practices* — all five happen every day of the week (Body
/// Map gets a new label each day; Sense of the Day cycles through
/// senses). The `dayOfWeek` field on each ritual is being used as
/// an ordinal position (ritual #1, #2, …) rather than a weekday
/// pinning. Labeling them Mon–Fri implied "this only happens on
/// Monday" which is the opposite of what the curriculum prescribes.
///
/// Sorted by `dayOfWeek` so the order the author intended is
/// preserved; the number itself is no longer rendered.
class _DailyList extends StatelessWidget {
  const _DailyList({required this.week});

  final WeekTemplate week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [...week.daily]
      ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
    if (ordered.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'DAILY RITUALS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < ordered.length; i++) ...[
          _RitualCard(ritual: ordered[i]),
          if (i < ordered.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _RitualCard extends StatelessWidget {
  const _RitualCard({required this.ritual});

  final DailyTemplate ritual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ritual.name, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            ritual.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.milestone, required this.accent});

  final MilestoneTemplate milestone;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Icon(
                Icons.flag_outlined,
                size: 18,
                color: accent,
              ),
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
          Text(milestone.name, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            milestone.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
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
