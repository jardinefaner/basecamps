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

/// Step-4 card: tap to select; tap selected card's left half →
/// inline title edit; tap right half → time picker. Tapping an
/// entry/override falls through to [onTap] (detail sheet) — entries
/// don't get inline edit because their schema is one-off and the
/// detail flow already covers them.
class _PlanCard extends ConsumerStatefulWidget {
  const _PlanCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final ScheduleItem item;
  final bool isSelected;
  final ValueChanged<ScheduleItem>? onTap;

  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  // Local state for inline title editing. Only enters this mode
  // when the card is already selected and the user taps the left
  // zone again — gives a clear two-step path (select, then edit)
  // that prevents accidental edits.
  bool _editingTitle = false;
  late final TextEditingController _titleController =
      TextEditingController(text: widget.item.title);
  final FocusNode _titleFocus = FocusNode();

  @override
  void didUpdateWidget(covariant _PlanCard old) {
    super.didUpdateWidget(old);
    // Card got deselected (selection moved elsewhere) → exit edit
    // mode without committing. The user can re-select and re-edit
    // if they meant to.
    if (old.isSelected && !widget.isSelected && _editingTitle) {
      _editingTitle = false;
    }
    // Source title changed (cloud sync, edit elsewhere) — refresh
    // the controller so the field reflects truth, but not while
    // the user is mid-edit (don't yank text out from under them).
    if (!_editingTitle && widget.item.title != _titleController.text) {
      _titleController.text = widget.item.title;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  bool get _isTemplate => widget.item.templateId != null;

  /// Tap on the LEFT half (title zone). State machine:
  ///   1. unselected → select
  ///   2. selected, not editing → enter edit mode (focus the
  ///      TextField)
  ///   3. selected, editing → no-op (the TextField has focus)
  void _onLeftZoneTap() {
    if (!_isTemplate) {
      widget.onTap?.call(widget.item);
      return;
    }
    if (!widget.isSelected) {
      ref
          .read(weekPlanSelectedTemplateProvider.notifier)
          .select(widget.item.templateId!);
      return;
    }
    // Already selected — enter title edit.
    setState(() => _editingTitle = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocus.requestFocus();
      _titleController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _titleController.text.length,
      );
    });
  }

  /// Tap on the RIGHT half (time zone). Same first-tap-selects
  /// pattern as the left zone, then a second tap pops the time
  /// picker.
  Future<void> _onRightZoneTap() async {
    if (!_isTemplate) {
      widget.onTap?.call(widget.item);
      return;
    }
    if (!widget.isSelected) {
      ref
          .read(weekPlanSelectedTemplateProvider.notifier)
          .select(widget.item.templateId!);
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: widget.item.startTimeOfDay,
      // We pick start time here; the new end time is start +
      // current duration so the user doesn't have to set both.
      // The full edit sheet (FAB → ✏️) lets them decouple.
      helpText: 'New start time',
    );
    if (picked == null || !mounted) return;
    final newStartMinutes = picked.minutesSinceMidnight;
    final duration = widget.item.endMinutes - widget.item.startMinutes;
    final newEndMinutes = newStartMinutes + duration;
    if (newEndMinutes >= 24 * 60) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text("That'd push the end past midnight."),
          ),
        );
      return;
    }
    final repo = ref.read(scheduleRepositoryProvider);
    await repo.shiftTemplateStart(
      templateId: widget.item.templateId!,
      newStartTime: Hhmm.fromMinutes(newStartMinutes),
      newEndTime: Hhmm.fromMinutes(newEndMinutes),
    );
  }

  /// Commit the title edit. Called on enter, on blur, or when
  /// selection moves away. Idempotent — no-op when the value
  /// hasn't changed.
  Future<void> _commitTitle() async {
    if (!_editingTitle) return;
    final trimmed = _titleController.text.trim();
    setState(() => _editingTitle = false);
    if (trimmed.isEmpty || trimmed == widget.item.title) {
      // Empty title is silently discarded (revert to what was
      // there). Same-as-before is a no-op write.
      _titleController.text = widget.item.title;
      return;
    }
    final repo = ref.read(scheduleRepositoryProvider);
    await repo.renameTemplate(
      templateId: widget.item.templateId!,
      newTitle: trimmed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final tinyDuration =
        item.endMinutes - item.startMinutes < 30; // <30 min = "tiny"
    final timeLabel = '${Hhmm.formatCompact(item.startTime)} – '
        '${Hhmm.formatCompact(item.endTime)}';

    final bg = widget.isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.95)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.85);
    final fg = widget.isSelected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onPrimaryContainer;
    final borderColor = widget.isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.primary.withValues(alpha: 0.18);
    const borderWidth = 1.5;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: _onLeftZoneTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                child: _editingTitle
                    ? TextField(
                        controller: _titleController,
                        focusNode: _titleFocus,
                        autofocus: true,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                        cursorColor: fg,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _commitTitle(),
                        onTapOutside: (_) => _commitTitle(),
                      )
                    : Text(
                        item.title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: tinyDuration ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
          ),
          // Hairline divider so the two tap zones read as distinct.
          Container(
            width: 0.5,
            height: double.infinity,
            color: fg.withValues(alpha: 0.2),
          ),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: _onRightZoneTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                child: tinyDuration
                    ? _RightCompactBody(
                        timeLabel: timeLabel,
                        color: fg,
                      )
                    : _RightStackedBody(
                        startLabel: Hhmm.formatCompact(item.startTime),
                        endLabel: Hhmm.formatCompact(item.endTime),
                        color: fg,
                        location: item.location,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RightCompactBody extends StatelessWidget {
  const _RightCompactBody({required this.timeLabel, required this.color});

  final String timeLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        timeLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color.withValues(alpha: 0.85),
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}

class _RightStackedBody extends StatelessWidget {
  const _RightStackedBody({
    required this.startLabel,
    required this.endLabel,
    required this.color,
    this.location,
  });

  final String startLabel;
  final String endLabel;
  final Color color;
  final String? location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          startLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          endLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color.withValues(alpha: 0.6),
          ),
        ),
        if (location != null && location!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              location!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );
  }
}
