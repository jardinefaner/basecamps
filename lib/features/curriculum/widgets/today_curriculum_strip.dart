import 'package:basecamp/core/format/color.dart';
import 'package:basecamp/features/activity_library/widgets/edit_library_item_sheet.dart';
import 'package:basecamp/features/curriculum/curriculum_today.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "Where in the curriculum are we today?" — a compact strip
/// rendered on Today (and reused on the Schedule editor) that
/// surfaces the current theme + week + today's daily-ritual cards.
///
/// What it shows when curriculum is authored:
///   * **Header chip** — `Bug week · Week 2 of 10`. Tappable; opens
///     the curriculum view scrolled to that week.
///   * **Core question card** — the morning-meeting prompt
///     authored on the lesson sequence (e.g. *"What makes me, me?"*).
///     Hidden when the sequence has none.
///   * **Today's cards** — the daily-ritual cards authored for this
///     calendar weekday. One row per card, tap → opens the activity
///     library editor for that card. Hidden when none.
///
/// What it shows otherwise:
///   * **Nothing.** Returns SizedBox.shrink. The screen renders as it
///     always did. This is purely additive — programs without
///     curriculum see no clutter.
///
/// All three sub-widgets live behind one Consumer so a single
/// `curriculumForDateProvider` watch drives them — no waterfall of
/// streams.
class TodayCurriculumStrip extends ConsumerWidget {
  const TodayCurriculumStrip({
    required this.date,
    this.compact = false,
    super.key,
  });

  /// Midnight-normalized date the strip resolves against. Pass the
  /// Today screen's `viewedDate` so cycling prev/next reflows the
  /// strip. Same value the schedule resolver already uses.
  final DateTime date;

  /// Drops the per-weekday daily-cards list when true. Used by the
  /// week-scoped Schedule editor where "today's cards" doesn't apply
  /// (the editor shows seven days at once); the chip + core question
  /// still render so the teacher sees what week they're authoring.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayAsync = ref.watch(curriculumForDateProvider(date));
    return dayAsync.maybeWhen(
      data: (day) {
        if (day == null) return const SizedBox.shrink();
        return _Body(date: date, day: day, compact: compact);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.date,
    required this.day,
    required this.compact,
  });

  final DateTime date;
  final CurriculumDay day;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = parseHex(day.sequence?.colorHex) ??
        parseHex(day.theme.colorHex) ??
        theme.colorScheme.primary;
    final coreQuestion = (day.sequence?.coreQuestion ?? '').trim();
    final todayCards = compact ? const <SequenceItemWithLibrary>[] : _todayCards(day, date);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(day: day, accent: accent),
          if (coreQuestion.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _CoreQuestionCard(question: coreQuestion, accent: accent),
          ],
          if (todayCards.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _TodayCardsList(
              cards: todayCards,
              accent: accent,
              date: date,
            ),
          ],
        ],
      ),
    );
  }

  /// All of this week's daily rituals — not filtered by weekday.
  /// Curriculum daily rituals are *parallel daily practices* (every
  /// ritual happens every day of the week), so "today's curriculum"
  /// is the full set, not a single day's slice. The `dayOfWeek` on
  /// each item is now an ordinal position used to keep the order
  /// stable; we sort by it but don't render it.
  static List<SequenceItemWithLibrary> _todayCards(
    CurriculumDay day,
    DateTime date,
  ) {
    final arc = day.arc;
    if (arc == null) return const [];
    final out = <SequenceItemWithLibrary>[];
    for (var d = 1; d <= 5; d++) {
      final items = arc.dailyByWeekday[d];
      if (items != null) out.addAll(items);
    }
    out.addAll(arc.dailyUnscheduled);
    return out;
  }
}

/// `Bug week · Week 2 of 10` chip with a colored leading dot. Tapping
/// pushes the curriculum view for the active theme so the teacher can
/// drill from "what week is it?" → the full multi-week arc.
class _Header extends StatelessWidget {
  const _Header({required this.day, required this.accent});

  final CurriculumDay day;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSequence = day.sequence != null;
    final weekLabel = hasSequence
        ? day.totalWeeks > 0
            ? 'Week ${day.weekIndex + 1} of ${day.totalWeeks}'
            : 'Week ${day.weekIndex + 1}'
        : 'Off-arc';
    final sequenceTitle = day.sequence?.name;
    final phase = (day.sequence?.phase ?? '').trim();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () =>
          context.push('/more/themes/${day.theme.id}/curriculum'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          day.theme.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '·',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        weekLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (sequenceTitle != null && sequenceTitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        // Strip the "Week N: " prefix when present so
                        // the chip reads "My World Inside" rather than
                        // "Week 1: My World Inside" (the week part is
                        // already shown above).
                        _stripWeekPrefix(sequenceTitle),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (phase.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        phase.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoreQuestionCard extends StatelessWidget {
  const _CoreQuestionCard({required this.question, required this.accent});

  final String question;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.question_mark_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "TODAY'S QUESTION",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  question,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's daily-ritual cards rendered as a thin list. Each row has
/// two affordances: tap the row → activity-library editor (read the
/// full prompt or scale to a different age); tap the calendar
/// "+" icon → activity wizard pre-filled with this card + today's
/// weekday so the curriculum lands on the schedule in two taps.
class _TodayCardsList extends StatelessWidget {
  const _TodayCardsList({
    required this.cards,
    required this.accent,
    required this.date,
  });

  final List<SequenceItemWithLibrary> cards;
  final Color accent;

  /// The strip's anchor date — passed through to each card row so
  /// the "+ Schedule" action seeds the activity wizard with the
  /// right weekday (today's vs. the cycled date the teacher is
  /// browsing).
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'DAILY RITUALS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            _CardRow(entry: cards[i], date: date),
          ],
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.entry, required this.date});

  final SequenceItemWithLibrary entry;

  /// Anchor date — used to seed the activity wizard's weekday when
  /// the teacher schedules from this row.
  final DateTime date;

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLibraryItemSheet(item: entry.library),
    );
  }

  /// Open the activity wizard pre-filled from this curriculum card.
  /// Mirror, not link — the resulting ScheduleTemplate is independent
  /// of the curriculum item. Edits to the curriculum card don't
  /// propagate, and edits to the schedule item don't write back. Two
  /// reasons:
  ///   1. Curriculum is "what we want to do this week"; schedule is
  ///      "when we're actually doing it." A teacher routinely tweaks
  ///      one without meaning the other.
  ///   2. Tracking the link would require schema (a curriculum_item_id
  ///      column on schedule_templates) and reverse-edit semantics
  ///      we haven't designed yet. The mirror is shippable today.
  Future<void> _schedule(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewActivityWizardScreen(
          initialLibraryItem: entry.library,
          // Seeds the wizard's weekday set so the recurring pattern
          // matches the curriculum (a Monday ritual schedules every
          // Monday by default; the teacher can narrow the date range
          // or add weekdays inside the wizard).
          initialDays: {date.weekday},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = (entry.library.summary ?? '').trim();
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.library.title,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            // "+ Schedule" — the materialization affordance. Sits
            // before the chevron so the chevron still reads as
            // "tap the row to open the card."
            IconButton(
              tooltip: 'Schedule',
              icon: const Icon(Icons.event_outlined, size: 18),
              color: theme.colorScheme.primary,
              visualDensity: VisualDensity.compact,
              onPressed: () => _schedule(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Strip leading "Week N:" or "Week N -" so the chip subtitle reads
/// the human title only. Tolerant of missing prefix — returns the
/// original string when no match.
String _stripWeekPrefix(String name) {
  final match =
      RegExp(r'^\s*week\s+\d+\s*[:\-–]\s*', caseSensitive: false)
          .firstMatch(name);
  if (match == null) return name;
  return name.substring(match.end);
}
