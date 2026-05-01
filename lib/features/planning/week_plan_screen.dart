import 'dart:async';

import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/core/format/time.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/ai/ai_activity_composer.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show groupsProvider;
import 'package:basecamp/features/export/export_actions.dart';
import 'package:basecamp/features/planning/week_plan_canvas.dart';
import 'package:basecamp/features/planning/week_plan_state.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// `/week-plan` — Monday-to-Friday column layout showing every
/// scheduled item on each day. Tap a card → [ActivityDetailSheet].
/// Long-press-drag a card onto another column to either move or
/// copy it — a bottom sheet asks which on every drop. Holding
/// Alt/Option while dropping skips the chooser and goes straight to
/// copy (Finder-style fast-path). Move semantics: template-backed
/// cards shift the recurring weekday (all future weeks); entry-
/// backed cards shift just that one occurrence's date. Copy semantics:
/// the original stays put and a clone (with the same group/adult/room
/// assignments) lands on the target day.
///
/// Trailing "Duplicate last week" action copies one-off entries from
/// the prior week forward onto their mirror day (templates already
/// recur, so they're skipped).
class WeekPlanScreen extends ConsumerStatefulWidget {
  const WeekPlanScreen({super.key});

  @override
  ConsumerState<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends ConsumerState<WeekPlanScreen> {
  // `_monday` migrated to `weekPlanWeekProvider` so the FAB, the
  // canvas, and the navigator all read the same source of truth.
  // Local state would have made tap-to-set-focused-day work but
  // duplicated the source of truth.

  DateTime get _monday => ref.read(weekPlanWeekProvider);

  void _shiftWeek(int deltaWeeks) {
    ref.read(weekPlanWeekProvider.notifier).shift(deltaWeeks);
  }

  String _rangeLabel() {
    final monday = _monday;
    final friday = monday.add(const Duration(days: 4));
    final sameMonth = monday.month == friday.month;
    if (sameMonth) {
      return '${DateFormat.MMMMd().format(monday)} – '
          '${DateFormat.d().format(friday)}';
    }
    return formatDateRange(monday, friday);
  }

  Future<void> _duplicateLastWeek() async {
    final repo = ref.read(scheduleRepositoryProvider);
    final monday = _monday;
    final sourceMonday = monday.subtract(const Duration(days: 7));
    final messenger = ScaffoldMessenger.of(context);
    final count = await repo.duplicateWeekTemplates(
      sourceMonday: sourceMonday,
      destMonday: monday,
    );
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Nothing one-off to duplicate from last week. '
                    '(Templates already recur.)'
                : 'Duplicated $count '
                    '${count == 1 ? 'entry' : 'entries'} from last week.',
          ),
        ),
      );
  }

  Future<void> _openDetail(ScheduleItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ActivityDetailSheet(item: item),
    );
  }

  /// Tap-already-selected handler. Replaces the previous FAB → ✏️
  /// flow: tapping a selected card opens its full edit sheet for
  /// the rare metadata edits (groups, room, notes, date range).
  Future<void> _openEditForCard(ScheduleItem item) async {
    final templateId = item.templateId;
    if (templateId == null) {
      await _openDetail(item);
      return;
    }
    final repo = ref.read(scheduleRepositoryProvider);
    final template = await repo.getTemplate(templateId);
    if (template == null || !mounted) return;
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => EditTemplateSheet(template: template),
    );
  }

  /// Manual create. **Every** new activity from the week plan now
  /// also creates an `activity_library` row, with the schedule
  /// template pointing back at it via `sourceLibraryItemId`. So:
  ///   * The library is the source of truth for an activity's
  ///     content; the template is just a *scheduling* of that
  ///     content at a particular day/time.
  ///   * Tapping the title in the today-tab activity modal opens
  ///     `LibraryCardDetailSheet` automatically — that route is
  ///     already gated on `sourceLibraryItemId != null`.
  ///   * The legacy `_PromoteToLibraryButton` keeps working for
  ///     templates that pre-date this change.
  ///
  /// Manual variant lands a blank library item; the user's first
  /// title keystroke (via the inline edit on the canvas) writes to
  /// the schedule_template only — library + template titles can
  /// drift if the user edits each independently. We don't propagate
  /// today; if that becomes painful we'll add a write-through path.
  Future<void> _onCreateAt({
    required int dayOfWeek,
    required int snappedStartMinutes,
  }) async {
    final scheduleRepo = ref.read(scheduleRepositoryProvider);
    final libraryRepo = ref.read(activityLibraryRepositoryProvider);
    final monday = ref.read(weekPlanWeekProvider);
    final groupFilter = ref.read(weekPlanGroupFilterProvider);
    final friday = monday.add(const Duration(days: 4));

    // Create the library item first so we have its id to pass as
    // sourceLibraryItemId on the template. Failure here bubbles out
    // and the template never gets created — better than orphaning a
    // template that points at a missing library row.
    final libraryItemId = await libraryRepo.addItem(
      title: '',
      defaultDurationMin: 30,
    );

    final newId = await scheduleRepo.addTemplate(
      dayOfWeek: dayOfWeek,
      startTime: Hhmm.fromMinutes(snappedStartMinutes),
      // Default 30-min duration. The user resizes via edge-drag or
      // the full edit sheet.
      endTime: Hhmm.fromMinutes(snappedStartMinutes + 30),
      title: '',
      groupIds: groupFilter == null ? const [] : [groupFilter],
      allGroups: groupFilter == null,
      startDate: monday,
      endDate: friday,
      sourceLibraryItemId: libraryItemId,
    );

    // Select + mark fresh so the card autofocuses its title input.
    ref.read(weekPlanSelectedTemplateProvider.notifier).select(newId);
    ref.read(weekPlanFreshCardProvider.notifier).mark(newId);
  }

  /// AI-create handler. Same library-first flow as `_onCreateAt`,
  /// but the library item is born already-populated with every
  /// field the AI generated:
  ///   * description → library.summary
  ///   * objectives  → library.learningGoals
  ///   * steps       → library.keyPoints
  ///   * materials   → library.materials
  ///   * duration    → library.defaultDurationMin (parsed)
  ///   * ageRange    → library.audienceMinAge / audienceMaxAge (parsed)
  ///   * link        → library.sourceUrl
  ///
  /// The schedule_template gets the title + a condensed `notes`
  /// (description) for the calendar preview. The full content lives
  /// on the library card, which the today-tab modal links to.
  Future<void> _onCreateAiAt({
    required int dayOfWeek,
    required int snappedStartMinutes,
  }) async {
    final activity = await showAiActivityComposer(context);
    if (!mounted || activity == null) return;
    if (activity.title.isEmpty && activity.description.isEmpty) {
      return;
    }

    final scheduleRepo = ref.read(scheduleRepositoryProvider);
    final libraryRepo = ref.read(activityLibraryRepositoryProvider);
    final monday = ref.read(weekPlanWeekProvider);
    final groupFilter = ref.read(weekPlanGroupFilterProvider);
    final friday = monday.add(const Duration(days: 4));

    final durationMin = _parseDurationMinutes(activity.duration);
    final (minAge, maxAge) = _parseAgeRange(activity.ageRange);

    final libraryItemId = await libraryRepo.addItem(
      title: activity.title,
      defaultDurationMin: durationMin ?? 30,
      summary: _orNull(activity.description),
      learningGoals: _orNull(activity.objectives),
      keyPoints: _orNull(activity.steps),
      materials: _orNull(activity.materials),
      audienceMinAge: minAge,
      audienceMaxAge: maxAge,
      sourceUrl: _orNull(activity.link),
    );

    final endMinutes =
        snappedStartMinutes + (durationMin ?? 30);

    final newId = await scheduleRepo.addTemplate(
      dayOfWeek: dayOfWeek,
      startTime: Hhmm.fromMinutes(snappedStartMinutes),
      endTime: Hhmm.fromMinutes(endMinutes),
      title: activity.title,
      // The notes here are a tiny preview for the calendar card; the
      // rich content lives on the library item.
      notes: _orNull(activity.description),
      sourceUrl: _orNull(activity.link),
      sourceLibraryItemId: libraryItemId,
      groupIds: groupFilter == null ? const [] : [groupFilter],
      allGroups: groupFilter == null,
      startDate: monday,
      endDate: friday,
    );
    // Select but don't mark fresh — AI cards land populated; popping
    // focus on a TextField the user didn't ask for would shove the
    // keyboard up unsolicited.
    ref.read(weekPlanSelectedTemplateProvider.notifier).select(newId);
  }

  /// Drop handler — fires when a long-press drag ends. Two paths:
  /// **move** (default) updates the source template's day + time;
  /// **duplicate** (alt held) clones the template and lands the
  /// clone at the snapped target. Both end with an Undo SnackBar
  /// — drag-by-mistake on a forever-recurring template would
  /// otherwise affect every week and recovery would mean digging
  /// through the edit sheet.
  Future<void> _onCardDrop({
    required String templateId,
    required int sourceDayOfWeek,
    required int targetDayOfWeek,
    required int snappedStartMinutes,
    required int snappedEndMinutes,
    required bool altHeld,
  }) async {
    final repo = ref.read(scheduleRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final weekdayLabel = _weekdayLabel(targetDayOfWeek);
    final timeLabel = Hhmm.fromMinutes(snappedStartMinutes);

    if (altHeld) {
      // Duplicate path. `copyTemplateToDay` clones onto the target
      // day with the source's start/end; we then shift the clone
      // to the snapped time. Two-step on purpose — the clone
      // method is shared with right-click → duplicate elsewhere.
      final newId = await repo.copyTemplateToDay(
        templateId: templateId,
        targetDay: targetDayOfWeek,
      );
      await repo.shiftTemplateStart(
        templateId: newId,
        newStartTime: Hhmm.fromMinutes(snappedStartMinutes),
        newEndTime: Hhmm.fromMinutes(snappedEndMinutes),
      );
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Duplicated to $weekdayLabel at $timeLabel.',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                await repo.deleteTemplate(newId);
              },
            ),
          ),
        );
      return;
    }

    // Move path. Update day + start + end as a single logical
    // shift. Day-only changes use moveTemplateToDay (cheaper); any
    // time change goes through shiftTemplateStart afterwards.
    if (targetDayOfWeek != sourceDayOfWeek) {
      await repo.moveTemplateToDay(
        templateId: templateId,
        newDayOfWeek: targetDayOfWeek,
      );
    }
    await repo.shiftTemplateStart(
      templateId: templateId,
      newStartTime: Hhmm.fromMinutes(snappedStartMinutes),
      newEndTime: Hhmm.fromMinutes(snappedEndMinutes),
    );
    if (!mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Moved to $weekdayLabel at $timeLabel.'),
          // No undo for move — the user can drag back if they
          // misclicked. Implementing precise undo would require
          // remembering the source's original day + time, which
          // is doable but adds state. Skip for v1.
        ),
      );
  }

  static String _weekdayLabel(int day) {
    switch (day) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      default:
        return 'day $day';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Read the visible week through Riverpod so back/forward
    // navigation rebuilds the canvas via provider invalidation.
    final monday = ref.watch(weekPlanWeekProvider);
    final scheduleAsync = ref.watch(scheduleForWeekProvider(monday));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Week plan'),
        actions: [
          TextButton.icon(
            onPressed: _duplicateLastWeek,
            icon: const Icon(Icons.content_copy_outlined, size: 18),
            label: const Text('Duplicate last week'),
          ),
          IconButton(
            tooltip: 'Export week',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => exportWeek(context, ref, monday),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      // FAB removed — empty-slot click is the canonical add path
      // and tap-on-selected opens the full edit sheet. Less chrome,
      // more direct manipulation.
      body: Column(
        children: [
          _WeekNavRow(
            label: _rangeLabel(),
            onPrev: () => _shiftWeek(-1),
            onNext: () => _shiftWeek(1),
            onReset: () =>
                ref.read(weekPlanWeekProvider.notifier).thisWeek(),
          ),
          // Group filter chip rail.
          const _GroupFilterRail(),
          Expanded(
            // When the side-panel adaptive sheet opens (web), shift
            // the canvas left by the panel's width so the rightmost
            // column (Friday) doesn't sit hidden underneath. Mobile
            // uses a bottom sheet which doesn't affect horizontal
            // layout, so the padding stays 0 there.
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(
                right:
                    ref.watch(adaptiveSidePanelWidthProvider) ?? 0,
              ),
              child: scheduleAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
                data: (byDay) => WeekPlanCanvas(
                  monday: monday,
                  byDay: byDay,
                  onTapCard: _openDetail,
                  onTapAlreadySelected: _openEditForCard,
                  onCreateAt: _onCreateAt,
                  onCreateAiAt: _onCreateAiAt,
                  onCardDrop: _onCardDrop,
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

/// Top header row: previous-week / next-week navigators + a date
/// range label + a "this week" home button. Drives
/// [weekPlanWeekProvider].
class _WeekNavRow extends StatelessWidget {
  const _WeekNavRow({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onReset,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: TextButton(
                  onPressed: onReset,
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

/// Group filter chip rail. "All" shows every template; each group
/// chip narrows the canvas to that group's items + the all-groups
/// templates (which apply to every group anyway).
class _GroupFilterRail extends ConsumerWidget {
  const _GroupFilterRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groupsAsync = ref.watch(groupsProvider);
    final selected = ref.watch(weekPlanGroupFilterProvider);
    return groupsAsync.when(
      loading: () => const SizedBox(height: 0),
      error: (_, _) => const SizedBox(height: 0),
      data: (groups) {
        if (groups.isEmpty) return const SizedBox(height: 0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: selected == null,
                onTap: () => ref
                    .read(weekPlanGroupFilterProvider.notifier)
                    .set(null),
                theme: theme,
              ),
              for (final g in groups) ...[
                const SizedBox(width: AppSpacing.xs),
                _FilterChip(
                  label: g.name,
                  selected: selected == g.id,
                  onTap: () => ref
                      .read(weekPlanGroupFilterProvider.notifier)
                      .set(g.id),
                  theme: theme,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Trims and returns null for empty strings — tightens the
/// `addItem(...)` / `addTemplate(...)` call sites since both repos
/// treat null as "field absent" but blank `""` as a real value, and
/// we don't want to persist whitespace-only fields the AI sometimes
/// emits when a key is unknown.
String? _orNull(String s) {
  final trimmed = s.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Best-effort minute parser for AI-generated duration strings like
/// "15 min", "30 minutes", "1 hour", "1 hr 15 min". Returns null when
/// nothing matches — the caller falls back to its default.
int? _parseDurationMinutes(String s) {
  if (s.trim().isEmpty) return null;
  // Capture every number-with-unit pair, then sum minutes + hours×60.
  // Handles "1 hour 15 minutes", "1h 30m", "45 min", etc.
  final matches = RegExp(
    r'(\d+)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b',
    caseSensitive: false,
  ).allMatches(s);
  if (matches.isEmpty) {
    // Fallback: a bare number means minutes ("15").
    final bare = RegExp(r'\d+').firstMatch(s);
    return bare == null ? null : int.tryParse(bare.group(0)!);
  }
  var total = 0;
  for (final m in matches) {
    final n = int.tryParse(m.group(1)!) ?? 0;
    final unit = m.group(2)!.toLowerCase();
    total += unit.startsWith('h') ? n * 60 : n;
  }
  return total > 0 ? total : null;
}

/// Best-effort age-range parser for AI-generated strings like
/// "3–5 years", "ages 4 to 6", "5". Returns (null, null) when
/// nothing matches.
(int?, int?) _parseAgeRange(String s) {
  if (s.trim().isEmpty) return (null, null);
  // Pair-of-numbers separated by hyphen / en-dash / em-dash / "to".
  final pair = RegExp(
    r'(\d+)\s*(?:-|–|—|to)\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(s);
  if (pair != null) {
    final lo = int.tryParse(pair.group(1)!);
    final hi = int.tryParse(pair.group(2)!);
    return (lo, hi);
  }
  // Single number — treat as both min and max.
  final single = RegExp(r'\d+').firstMatch(s);
  if (single != null) {
    final n = int.tryParse(single.group(0)!);
    return (n, n);
  }
  return (null, null);
}
