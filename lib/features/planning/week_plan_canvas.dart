import 'package:basecamp/core/format/time.dart';
import 'package:basecamp/features/planning/week_plan_state.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Vertical-timeline week plan canvas. Five day columns
/// (Mon–Fri); cards positioned by time, sized by duration. Step 2:
/// static layout only — no tap-to-select, drag, or inline edit yet
/// (those land in steps 3–7).
///
/// Layout math is centralized in [WeekPlanScale] so the FAB add /
/// drag-to-snap math in later steps reads off the same axis.

const double _kPxPerMinute = 0.8;
const double _kHourLabelWidth = 56;
const double _kColumnHeaderHeight = 40;

class WeekPlanScale {
  const WeekPlanScale({
    required this.dayStartMinutes,
    required this.dayEndMinutes,
  });

  /// Computes a sensible day window from the items in this week.
  /// Pads to round hours, clamps to a minimum 7am-5pm so an empty
  /// week still shows a usable canvas.
  factory WeekPlanScale.from(Iterable<ScheduleItem> items) {
    var earliest = 7 * 60;
    var latest = 17 * 60;
    var seen = false;
    for (final item in items) {
      if (item.isFullDay) continue;
      seen = true;
      if (item.startMinutes < earliest) earliest = item.startMinutes;
      if (item.endMinutes > latest) latest = item.endMinutes;
    }
    if (!seen) {
      // Empty week — keep the friendly default.
      return const WeekPlanScale(
        dayStartMinutes: 7 * 60,
        dayEndMinutes: 17 * 60,
      );
    }
    // Round outward to whole hours so the hour rule lines line up
    // with the visible window.
    final dayStart = (earliest ~/ 60) * 60;
    final dayEndCandidate = ((latest + 59) ~/ 60) * 60;
    return WeekPlanScale(
      dayStartMinutes: dayStart,
      dayEndMinutes: dayEndCandidate < dayStart + 60
          ? dayStart + 60
          : dayEndCandidate,
    );
  }

  final int dayStartMinutes;
  final int dayEndMinutes;

  int get totalMinutes => dayEndMinutes - dayStartMinutes;
  double get totalHeight => totalMinutes * _kPxPerMinute;

  /// Pixel offset (top) for a given minutes-since-midnight.
  double yFor(int minutes) =>
      (minutes - dayStartMinutes) * _kPxPerMinute;

  /// Inverse of [yFor] — used by drag/snap in step 5.
  int minutesAtY(double y) =>
      dayStartMinutes + (y / _kPxPerMinute).round();
}

class WeekPlanCanvas extends ConsumerWidget {
  const WeekPlanCanvas({
    required this.monday,
    required this.byDay,
    this.onTapCard,
    super.key,
  });

  /// Monday of the visible week, midnight local. Drives the column
  /// header dates.
  final DateTime monday;

  /// Items per ISO weekday (1..5). The repo already filters by
  /// week-overlap upstream; this widget just renders.
  final Map<int, List<ScheduleItem>> byDay;

  /// Step-3 hook. Static for now; tapping a card does nothing.
  final ValueChanged<ScheduleItem>? onTapCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groupFilter = ref.watch(weekPlanGroupFilterProvider);
    final selectedId = ref.watch(weekPlanSelectedTemplateProvider);
    final visibleByDay = <int, List<ScheduleItem>>{
      for (var d = 1; d <= scheduleDayCount; d++)
        d: _filterByGroup(byDay[d] ?? const [], groupFilter),
    };
    final scale = WeekPlanScale.from(
      visibleByDay.values.expand((items) => items),
    );

    return GestureDetector(
      // Tap on the canvas background (anywhere outside a card)
      // clears the selection. behavior: opaque so the gesture
      // catches taps on the empty canvas area / hour gutter / day
      // headers, not just on the visible Padding pixels.
      behavior: HitTestBehavior.opaque,
      onTap: () => ref
          .read(weekPlanSelectedTemplateProvider.notifier)
          .clear(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          // The whole canvas scrolls vertically — long days
          // (early arrival to late pickup) stay browsable on
          // small viewports.
          child: SizedBox(
            height:
                _kColumnHeaderHeight + scale.totalHeight + AppSpacing.md,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HourGutter(scale: scale, theme: theme),
                for (var d = 1; d <= scheduleDayCount; d++) ...[
                  Expanded(
                    child: _DayColumn(
                      date: monday.add(Duration(days: d - 1)),
                      weekday: d,
                      items: visibleByDay[d] ?? const [],
                      scale: scale,
                      selectedId: selectedId,
                      onTapCard: onTapCard,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Filter visible templates by the active group filter.
  ///   * null filter → show everything (every group + all-groups).
  ///   * specific groupId → show templates scoped to that group +
  ///     all-groups templates (which apply to every group anyway).
  ///
  /// Future enhancement: if a teacher wants to see *only* their
  /// group's items (no all-groups noise), add a "strict" toggle.
  /// Skip for v1 — most planning sessions want to see all-groups
  /// in context.
  static List<ScheduleItem> _filterByGroup(
    List<ScheduleItem> items,
    String? groupFilter,
  ) {
    if (groupFilter == null) return items;
    return [
      for (final item in items)
        if (item.isAllGroups || item.groupIds.contains(groupFilter))
          item,
    ];
  }
}

/// Left-side rail of hour labels. Ticks every hour; labels every
/// hour. The ticks line up with each [_DayColumn]'s grid lines.
class _HourGutter extends StatelessWidget {
  const _HourGutter({required this.scale, required this.theme});

  final WeekPlanScale scale;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hourCount =
        ((scale.totalMinutes + 59) / 60).floor();
    return SizedBox(
      width: _kHourLabelWidth,
      child: Padding(
        padding: const EdgeInsets.only(top: _kColumnHeaderHeight),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var h = 0; h <= hourCount; h++)
              Positioned(
                top: h * 60 * _kPxPerMinute - 7,
                right: AppSpacing.xs,
                child: Text(
                  Hhmm.formatCompactTimeOfDay(
                    TimeOfDay(
                      hour: ((scale.dayStartMinutes + h * 60) ~/ 60) % 24,
                      minute: 0,
                    ),
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.date,
    required this.weekday,
    required this.items,
    required this.scale,
    required this.selectedId,
    required this.onTapCard,
  });

  final DateTime date;
  final int weekday;
  final List<ScheduleItem> items;
  final WeekPlanScale scale;
  final String? selectedId;
  final ValueChanged<ScheduleItem>? onTapCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = _isToday(date);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row: weekday + date. Highlights today.
          SizedBox(
            height: _kColumnHeaderHeight,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat.E().format(date).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isToday
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.6,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    DateFormat.d().format(date),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isToday
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Body: hour grid + cards positioned absolutely.
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  // Hour rule lines.
                  for (var h = 0;
                      h <= ((scale.totalMinutes + 59) / 60).floor();
                      h++)
                    Positioned(
                      top: h * 60 * _kPxPerMinute,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 0.5,
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  // 30-min sub-ticks.
                  for (var h = 0;
                      h * 60 + 30 < scale.totalMinutes;
                      h++)
                    Positioned(
                      top: (h * 60 + 30) * _kPxPerMinute,
                      left: 8,
                      right: 8,
                      child: Container(
                        height: 0.5,
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.18),
                      ),
                    ),
                  // The cards.
                  for (final item in items)
                    if (!item.isFullDay)
                      Positioned(
                        top: scale.yFor(item.startMinutes),
                        left: 4,
                        right: 4,
                        height: (item.endMinutes - item.startMinutes) *
                                _kPxPerMinute -
                            2,
                        child: _PlanCard(
                          item: item,
                          isSelected: item.templateId != null &&
                              item.templateId == selectedId,
                          onTap: onTapCard,
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

/// Step-3 card: tap selects template-backed cards (drives the FAB
/// transform on the screen). Tapping an entry/override falls through
/// to [onTap] which still opens the activity detail sheet — entries
/// don't get inline edit because their schema is one-off and the
/// detail flow already covers them. Steps 4–5 add inline edit and
/// drag.
class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final ScheduleItem item;
  final bool isSelected;
  final ValueChanged<ScheduleItem>? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tinyDuration =
        item.endMinutes - item.startMinutes < 30; // <30 min = "tiny"
    final timeLabel = '${Hhmm.formatCompact(item.startTime)} – '
        '${Hhmm.formatCompact(item.endTime)}';

    final isTemplate = item.templateId != null;
    final bg = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.95)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.85);
    final fg = isSelected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onPrimaryContainer;
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.primary.withValues(alpha: 0.25);
    final borderWidth = isSelected ? 1.5 : 0.5;

    return InkWell(
      onTap: () {
        if (isTemplate) {
          // Tap template card → select it (drives FAB → ✏️).
          // Selection stops the gesture from propagating up to the
          // canvas's deselect-on-tap-outside detector.
          ref
              .read(weekPlanSelectedTemplateProvider.notifier)
              .select(item.templateId!);
        } else {
          // Entry / override / one-off — selection isn't the right
          // affordance, just open the detail sheet directly.
          onTap?.call(item);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: tinyDuration
            ? _CompactBody(
                title: item.title,
                timeLabel: timeLabel,
                color: fg,
              )
            : _StackedBody(
                title: item.title,
                timeLabel: timeLabel,
                color: fg,
                location: item.location,
              ),
      ),
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({
    required this.title,
    required this.timeLabel,
    required this.color,
  });

  final String title;
  final String timeLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          timeLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

class _StackedBody extends StatelessWidget {
  const _StackedBody({
    required this.title,
    required this.timeLabel,
    required this.color,
    this.location,
  });

  final String title;
  final String timeLabel;
  final Color color;
  final String? location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        const SizedBox(height: 2),
        Text(
          timeLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color.withValues(alpha: 0.75),
          ),
        ),
        if (location != null && location!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              location!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color.withValues(alpha: 0.65),
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
