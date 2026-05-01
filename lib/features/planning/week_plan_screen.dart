import 'dart:async';

import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/core/format/time.dart';
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

  /// Empty-slot click handler. Creates a fresh card scoped to the
  /// visible week with the snapped slot's start time. Marks the
  /// new id as the fresh-card so the title TextField autofocuses
  /// on its first build.
  Future<void> _onCreateAt({
    required int dayOfWeek,
    required int snappedStartMinutes,
  }) async {
    final repo = ref.read(scheduleRepositoryProvider);
    final monday = ref.read(weekPlanWeekProvider);
    final groupFilter = ref.read(weekPlanGroupFilterProvider);
    final friday = monday.add(const Duration(days: 4));

    final newId = await repo.addTemplate(
      dayOfWeek: dayOfWeek,
      startTime: Hhmm.fromMinutes(snappedStartMinutes),
      // Default 30-min duration. The user resizes via edge-drag
      // (next commit) or via the full edit sheet.
      endTime: Hhmm.fromMinutes(snappedStartMinutes + 30),
      title: '',
      groupIds: groupFilter == null ? const [] : [groupFilter],
      allGroups: groupFilter == null,
      startDate: monday,
      endDate: friday,
    );

    // Select + mark fresh so the card autofocuses its title input.
    ref.read(weekPlanSelectedTemplateProvider.notifier).select(newId);
    ref.read(weekPlanFreshCardProvider.notifier).mark(newId);
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
