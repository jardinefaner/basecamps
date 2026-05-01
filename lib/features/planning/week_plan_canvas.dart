import 'package:basecamp/core/format/time.dart';
import 'package:basecamp/features/planning/week_plan_state.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Vertical-timeline week plan canvas. Five day columns
/// (Mon–Fri); cards positioned by time, sized by duration. Step 2:
/// static layout only — no tap-to-select, drag, or inline edit yet
/// (those land in steps 3–7).
///
/// Layout math is centralized in [WeekPlanScale] so the FAB add /
/// drag-to-snap math in later steps reads off the same axis.

/// Vertical scale: 2.5 px per minute. Tuned so a 30-min activity
/// (the typical kindergarten block size) renders at ~75dp tall,
/// which against a 220dp column width gives the **3:1 horizontal
/// aspect ratio** the user wanted for cards.
///
/// Duration still maps proportionally — a 15-min card is half the
/// height of a 30-min, a 60-min is twice — but the typical card
/// lands at 3:1 so titles + time read cleanly without feeling
/// cramped vertically.
const double _kPxPerMinute = 2.5;
const double _kHourLabelWidth = 56;
const double _kColumnHeaderHeight = 40;

/// Fixed per-day column width. Earlier the canvas used `Expanded`
/// per column so 5 days squeezed into the viewport, but the user
/// wanted real estate for each card to read like the rest of the
/// app's cards. With a fixed column width the canvas can grow
/// wider than the viewport and the outer wraps it in horizontal
/// scroll. 220dp paired with `_kPxPerMinute = 2.5` gives a 30-min
/// card a 3:1 aspect ratio.
const double _kDayColumnWidth = 220;

class WeekPlanScale {
  const WeekPlanScale({
    required this.dayStartMinutes,
    required this.dayEndMinutes,
  });

  /// Computes a sensible day window from the items in this week.
  /// Pads to round hours, clamps to a minimum 7am-6pm so an empty
  /// week still shows a usable canvas. (6pm default mirrors a
  /// typical full school day; earlier 5pm cut off pickup-time
  /// activities.)
  factory WeekPlanScale.from(Iterable<ScheduleItem> items) {
    var earliest = 7 * 60;
    var latest = 18 * 60;
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
        dayEndMinutes: 18 * 60,
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

class WeekPlanCanvas extends ConsumerStatefulWidget {
  const WeekPlanCanvas({
    required this.monday,
    required this.byDay,
    required this.onTapAlreadySelected,
    required this.onCreateAt,
    this.onTapCard,
    this.onCardDrop,
    super.key,
  });

  /// Monday of the visible week, midnight local. Drives the column
  /// header dates.
  final DateTime monday;

  /// Items per ISO weekday (1..5). The repo already filters by
  /// week-overlap upstream; this widget just renders.
  final Map<int, List<ScheduleItem>> byDay;

  /// Tap callback for entry-backed cards (template cards select
  /// in-place). Null = read-only mode.
  final ValueChanged<ScheduleItem>? onTapCard;

  /// Drop callback fired when a long-press drag completes. Owner
  /// (the screen) interprets the snapped target and calls the repo
  /// — keeps drag-effect policy decisions (move vs duplicate, undo
  /// affordance, snackbars) at the screen level instead of leaking
  /// into the canvas widget.
  final WeekPlanDropHandler? onCardDrop;

  /// Fires when a template card is tapped while it's already
  /// selected. The screen uses this to open the full edit sheet —
  /// replaces the FAB → ✏️ flow.
  final ValueChanged<ScheduleItem> onTapAlreadySelected;

  /// Click on an empty 15-min slot. Receives the snapped start
  /// minute + the day-of-week so the screen can `addTemplate(...)`
  /// and mark the new id as fresh-card for autofocus.
  final Future<void> Function({
    required int dayOfWeek,
    required int snappedStartMinutes,
  }) onCreateAt;

  @override
  ConsumerState<WeekPlanCanvas> createState() => _WeekPlanCanvasState();
}

/// Drop callback shape. The canvas computes the snapped target
/// (day + start time + alt-key state) and hands it to the screen
/// to commit.
typedef WeekPlanDropHandler = Future<void> Function({
  required String templateId,
  required int sourceDayOfWeek,
  required int targetDayOfWeek,
  required int snappedStartMinutes,
  required int snappedEndMinutes,
  required bool altHeld,
});

class _WeekPlanCanvasState extends ConsumerState<WeekPlanCanvas> {
  // GlobalKey on the canvas body so the drop handler can convert
  // global pointer coords → canvas-local for the snap math.
  final GlobalKey _canvasBodyKey = GlobalKey();

  // Vertical scroll controller — used to auto-scroll to "now" when
  // the canvas first mounts so the teacher lands looking at the
  // current time slot with prior + upcoming activities flanking it.
  final ScrollController _vScroll = ScrollController();
  bool _didCenterOnNow = false;

  @override
  void dispose() {
    _vScroll.dispose();
    super.dispose();
  }

  /// Schedule a one-shot scroll-to-now after the first layout pass.
  /// Centers the current time vertically in the visible viewport so
  /// the user sees what just happened + what's coming up next.
  void _scheduleCenterOnNow(WeekPlanScale scale) {
    if (_didCenterOnNow) return;
    _didCenterOnNow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vScroll.hasClients) return;
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      // Bail if "now" sits outside the day window — teacher's
      // working at 11pm? Don't yank them somewhere weird; let
      // them start at the top.
      if (nowMinutes < scale.dayStartMinutes ||
          nowMinutes > scale.dayEndMinutes) {
        return;
      }
      final nowY = scale.yFor(nowMinutes) + _kColumnHeaderHeight;
      final viewport = _vScroll.position.viewportDimension;
      final maxScroll = _vScroll.position.maxScrollExtent;
      // Aim for "now" to land at viewport-center. Clamp to the
      // valid scroll range so a short window doesn't try to
      // scroll past the end.
      final desired = (nowY - viewport / 2).clamp(0.0, maxScroll);
      _vScroll.jumpTo(desired);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupFilter = ref.watch(weekPlanGroupFilterProvider);
    final selectedId = ref.watch(weekPlanSelectedTemplateProvider);
    final dragState = ref.watch(weekPlanDragProvider);
    final visibleByDay = <int, List<ScheduleItem>>{
      for (var d = 1; d <= scheduleDayCount; d++)
        d: _filterByGroup(widget.byDay[d] ?? const [], groupFilter),
    };
    final scale = WeekPlanScale.from(
      visibleByDay.values.expand((items) => items),
    );
    _scheduleCenterOnNow(scale);

    const canvasWidth =
        _kHourLabelWidth + _kDayColumnWidth * scheduleDayCount;
    final canvasHeight =
        _kColumnHeaderHeight + scale.totalHeight + AppSpacing.md;

    return GestureDetector(
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
            // Outer = horizontal scroll. Inner = vertical scroll.
            // Both axes scroll independently. Each column is a fixed
            // width so cards have enough room to render in the
            // standard app-card look; the canvas can grow wider
            // than the viewport on narrow screens.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: canvasWidth,
                child: SingleChildScrollView(
                  controller: _vScroll,
                  child: Stack(
                    // Stack lets the ghost-overlay paint on top of
                    // the columns without affecting layout.
                    children: [
                      SizedBox(
                        key: _canvasBodyKey,
                        width: canvasWidth,
                        height: canvasHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HourGutter(scale: scale, theme: theme),
                            for (var d = 1;
                                d <= scheduleDayCount;
                                d++)
                              SizedBox(
                                width: _kDayColumnWidth,
                                child: _DayColumn(
                                  date: widget.monday
                                      .add(Duration(days: d - 1)),
                                  weekday: d,
                                  items: visibleByDay[d] ?? const [],
                                  scale: scale,
                                  selectedId: selectedId,
                                  dragState: dragState,
                                  onTapCard: widget.onTapCard,
                                  onTapAlreadySelected:
                                      widget.onTapAlreadySelected,
                                  onLongPressEnd: _onLongPressEnd,
                                  onCreateAt: (snappedStart) =>
                                      widget.onCreateAt(
                                    dayOfWeek: d,
                                    snappedStartMinutes: snappedStart,
                                  ),
                                ),
                              ),
                          ],
                        ),
                  ),
                  // Ghost overlay — rendered during the active
                  // drag, follows live pointer.
                  if (dragState != null)
                    _DragGhost(
                      state: dragState,
                      scale: scale,
                      canvasKey: _canvasBodyKey,
                      theme: theme,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Convert a canvas-local position to (day, snapped start
  /// minutes). Used by the tentative-mode commit — the canvas
  /// captures `globalToLocal(pointer)` once at release time and
  /// stores the result in `pinnedCanvasLocal`, so a later scroll
  /// doesn't slide the pin off its time slot.
  ({int dayOfWeek, int snappedStartMinutes})? _snapTargetFromCanvasLocal({
    required Offset canvasLocal,
    required Offset pickupLocal,
    required WeekPlanScale scale,
    required int durationMinutes,
  }) {
    final box =
        _canvasBodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final canvasSize = box.size;
    if (canvasLocal.dx < 0 ||
        canvasLocal.dy < 0 ||
        canvasLocal.dx > canvasSize.width ||
        canvasLocal.dy > canvasSize.height) {
      return null;
    }

    // Day-column math. Hour gutter takes a fixed `_kHourLabelWidth`
    // off the left; each column is `_kDayColumnWidth` wide. Index
    // clamps to [0..4] so a drop on the gutter or past Friday
    // still lands on a real column.
    final colIndex =
        ((canvasLocal.dx - _kHourLabelWidth) / _kDayColumnWidth)
            .floor();
    final dayOfWeek = colIndex.clamp(0, scheduleDayCount - 1) + 1;

    // Time math. The card's TOP should land at the snapped time —
    // not where the finger was. So we subtract the pickup offset's
    // dy from the canvas-local y to get the new top, then convert
    // top-y → minutes.
    final cardTopLocalY = canvasLocal.dy - pickupLocal.dy;
    // Subtract the column header so 0 lines up with the body's
    // top, which is where `scale.minutesAtY(0)` returns
    // `dayStartMinutes`.
    final bodyY = cardTopLocalY - _kColumnHeaderHeight;
    final rawMinutes = scale.minutesAtY(bodyY);
    final snapped = ((rawMinutes / 15).round() * 15).clamp(
      scale.dayStartMinutes,
      scale.dayEndMinutes - durationMinutes,
    );

    return (
      dayOfWeek: dayOfWeek,
      snappedStartMinutes: snapped,
    );
  }

  /// Drag-end handler. Computes the snap target from the live
  /// pointer position and fires the drop callback immediately on
  /// release. No tentative-confirm step — the canvas's
  /// auto-scroll-near-edges (added in the next phase) handles long
  /// moves where the source and target don't fit in viewport.
  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    final dragState = ref.read(weekPlanDragProvider);
    final altHeld = HardwareKeyboard.instance.isAltPressed;
    ref.read(weekPlanDragProvider.notifier).clear();
    if (dragState == null) return;
    final box =
        _canvasBodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final canvasLocal = box.globalToLocal(dragState.pointerGlobal);
    final groupFilter = ref.read(weekPlanGroupFilterProvider);
    final visibleByDay = <int, List<ScheduleItem>>{
      for (var d = 1; d <= scheduleDayCount; d++)
        d: _filterByGroup(
          widget.byDay[d] ?? const [],
          groupFilter,
        ),
    };
    final scale = WeekPlanScale.from(
      visibleByDay.values.expand((items) => items),
    );
    final target = _snapTargetFromCanvasLocal(
      canvasLocal: canvasLocal,
      pickupLocal: dragState.pickupOffsetLocal,
      scale: scale,
      durationMinutes: dragState.durationMinutes,
    );
    if (target == null) return;
    if (!altHeld &&
        target.dayOfWeek == dragState.sourceDayOfWeek &&
        target.snappedStartMinutes == dragState.sourceStartMinutes) {
      return; // no-op move
    }
    final snappedEnd =
        target.snappedStartMinutes + dragState.durationMinutes;
    await widget.onCardDrop?.call(
      templateId: dragState.templateId,
      sourceDayOfWeek: dragState.sourceDayOfWeek,
      targetDayOfWeek: target.dayOfWeek,
      snappedStartMinutes: target.snappedStartMinutes,
      snappedEndMinutes: snappedEnd,
      altHeld: altHeld,
    );
  }

  /// Filter visible templates by the active group filter.
  ///   * null filter → show everything (every group + all-groups).
  ///   * specific groupId → show templates scoped to that group +
  ///     all-groups templates (which apply to every group anyway).
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

class _DayColumn extends ConsumerStatefulWidget {
  const _DayColumn({
    required this.date,
    required this.weekday,
    required this.items,
    required this.scale,
    required this.selectedId,
    required this.dragState,
    required this.onTapCard,
    required this.onTapAlreadySelected,
    required this.onLongPressEnd,
    required this.onCreateAt,
  });

  final DateTime date;
  final int weekday;
  final List<ScheduleItem> items;
  final WeekPlanScale scale;
  final String? selectedId;
  final WeekPlanDragState? dragState;
  final ValueChanged<ScheduleItem>? onTapCard;
  final ValueChanged<ScheduleItem> onTapAlreadySelected;
  final void Function(LongPressEndDetails) onLongPressEnd;
  final Future<void> Function(int snappedStartMinutes) onCreateAt;

  @override
  ConsumerState<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends ConsumerState<_DayColumn> {
  /// Hovered slot's start minute, snapped to 15. Null when the
  /// pointer is off the column body. Drives the faint hover
  /// outline so the user can see where a click would land.
  int? _hoveredSlotStart;

  /// Round the local-y to the slot start that contains it.
  int _slotStartFromLocalY(double localY) {
    final raw = widget.scale.minutesAtY(localY);
    final floor15 = (raw ~/ 15) * 15;
    return floor15.clamp(
      widget.scale.dayStartMinutes,
      widget.scale.dayEndMinutes - 15,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = _isToday(widget.date);
    final scale = widget.scale;

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
                    DateFormat.E().format(widget.date).toUpperCase(),
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
                    DateFormat.d().format(widget.date),
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
          // Body: hour grid + empty-slot hover/click + cards.
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                clipBehavior: Clip.none,
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
                  // Empty-slot hover + tap-to-create layer. Sits
                  // BELOW the cards so card hits beat empty-slot
                  // hits — the empty-slot detector only fires on
                  // the gaps between cards.
                  Positioned.fill(
                    child: MouseRegion(
                      onHover: (event) {
                        final slot =
                            _slotStartFromLocalY(event.localPosition.dy);
                        if (slot != _hoveredSlotStart) {
                          setState(() => _hoveredSlotStart = slot);
                        }
                      },
                      onExit: (_) =>
                          setState(() => _hoveredSlotStart = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) async {
                          final slot = _slotStartFromLocalY(
                            details.localPosition.dy,
                          );
                          await widget.onCreateAt(slot);
                        },
                      ),
                    ),
                  ),
                  // Hovered-slot outline. Painted over the gesture
                  // layer (same Stack child order) so it stays
                  // readable even when the cursor moves fast.
                  if (_hoveredSlotStart != null)
                    Positioned(
                      top: scale.yFor(_hoveredSlotStart!),
                      left: 4,
                      right: 4,
                      height: 15 * _kPxPerMinute,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // The cards. Hidden when this card is the drag
                  // source — the ghost overlay paints in its place.
                  for (final item in widget.items)
                    if (!item.isFullDay)
                      Positioned(
                        top: scale.yFor(item.startMinutes),
                        left: 4,
                        right: 4,
                        height: (item.endMinutes - item.startMinutes) *
                                _kPxPerMinute -
                            2,
                        child: Opacity(
                          opacity:
                              widget.dragState?.templateId == item.templateId
                                  ? 0.25
                                  : 1,
                          child: _PlanCard(
                            item: item,
                            weekday: widget.weekday,
                            isSelected: item.templateId != null &&
                                item.templateId == widget.selectedId,
                            onTap: widget.onTapCard,
                            onTapAlreadySelected: widget.onTapAlreadySelected,
                            onLongPressEnd: widget.onLongPressEnd,
                          ),
                        ),
                      ),
                  // Selected-card time chips. Top-left = start;
                  // bottom-left = end. Painted outside the card via
                  // negative offsets (clipBehavior: Clip.none on the
                  // body Stack so this works).
                  for (final item in widget.items)
                    if (item.templateId != null &&
                        item.templateId == widget.selectedId)
                      ..._buildTimeChips(item, scale, theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Render the start + end time chips for a selected card. Each
  /// chip is a `Positioned` widget anchored *outside* the card via
  /// negative offsets — start chip pokes above the top edge, end
  /// chip pokes below the bottom edge. Both use compact "9:00a"
  /// format so they read fast.
  List<Widget> _buildTimeChips(
    ScheduleItem item,
    WeekPlanScale scale,
    ThemeData theme,
  ) {
    return [
      Positioned(
        top: scale.yFor(item.startMinutes) - 14,
        left: 4,
        child: _TimeChip(
          label: Hhmm.formatCompact(item.startTime),
          theme: theme,
        ),
      ),
      Positioned(
        top: scale.yFor(item.endMinutes) - 6,
        left: 4,
        child: _TimeChip(
          label: Hhmm.formatCompact(item.endTime),
          theme: theme,
        ),
      ),
    ];
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

/// Small time chip floating outside the selected card. Renders as
/// a pill with the start/end label in primary color.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

/// Plan card for the week canvas.
///
///   * Body shows just the title — the canonical AppCard look.
///     Times read from the side chips (`_TimeChip`, painted by the
///     parent column) and the hour rail on the left.
///   * Tap unselected → select. Tap already-selected → fires
///     `onTapAlreadySelected` which opens the full edit sheet.
///   * Long-press + drag → move (existing snap-to-15 commit-on-
///     release).
///   * Fresh-card mode (id matches `weekPlanFreshCardProvider`) →
///     title TextField autofocuses; commit on Enter or blur. Empty
///     title → delete the row (gives the user a clean cancel path
///     for accidental empty-slot clicks).
class _PlanCard extends ConsumerStatefulWidget {
  const _PlanCard({
    required this.item,
    required this.weekday,
    required this.isSelected,
    required this.onTap,
    required this.onTapAlreadySelected,
    required this.onLongPressEnd,
  });

  final ScheduleItem item;
  final int weekday;
  final bool isSelected;
  final ValueChanged<ScheduleItem>? onTap;
  final ValueChanged<ScheduleItem> onTapAlreadySelected;
  final void Function(LongPressEndDetails) onLongPressEnd;

  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.item.title);
  final FocusNode _titleFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Fresh-card → autofocus on first build.
    final fresh = ref.read(weekPlanFreshCardProvider);
    if (fresh != null && fresh == widget.item.templateId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _titleFocus.requestFocus();
        _titleController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _titleController.text.length,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant _PlanCard old) {
    super.didUpdateWidget(old);
    // Source title changed (cloud sync, edit elsewhere) — refresh
    // the controller so the field reflects truth, but not while
    // the user is mid-edit (don't yank text out from under them).
    if (!_titleFocus.hasFocus &&
        widget.item.title != _titleController.text) {
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
  bool get _isFresh =>
      ref.watch(weekPlanFreshCardProvider) == widget.item.templateId;

  void _onTap() {
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
    // Already selected → second tap opens the full edit sheet.
    widget.onTapAlreadySelected(widget.item);
  }

  /// Commit the title from the fresh-card TextField. Called on
  /// Enter or `onTapOutside`. Empty title → delete the row (clean
  /// cancel path for accidental empty-slot clicks).
  Future<void> _commitTitle() async {
    if (!_isFresh) return;
    final trimmed = _titleController.text.trim();
    final repo = ref.read(scheduleRepositoryProvider);
    if (trimmed.isEmpty) {
      await repo.deleteTemplate(widget.item.templateId!);
      ref.read(weekPlanFreshCardProvider.notifier).clear();
      return;
    }
    if (trimmed != widget.item.title) {
      await repo.renameTemplate(
        templateId: widget.item.templateId!,
        newTitle: trimmed,
      );
    }
    ref.read(weekPlanFreshCardProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    // Match the AppCard look used everywhere else in the app:
    //   * default — neutral card surface, transparent border (kept
    //     at 1.5px so selection doesn't shift layout)
    //   * selected — `primaryContainer.withValues(alpha: 0.55)` fill
    //     + 1.5px primary outline
    final isSelected = widget.isSelected;
    final cardColor = isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : theme.colorScheme.surfaceContainerHigh;
    final fg = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final borderColor =
        isSelected ? theme.colorScheme.primary : Colors.transparent;
    const borderWidth = 1.5;

    final isFresh = _isFresh;
    final card = Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isFresh ? null : _onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          child: isFresh
              ? TextField(
                  controller: _titleController,
                  focusNode: _titleFocus,
                  autofocus: true,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: fg,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: 'Activity name…',
                    hintStyle: theme.textTheme.titleSmall?.copyWith(
                      color: fg.withValues(alpha: 0.5),
                    ),
                  ),
                  onSubmitted: (_) => _commitTitle(),
                  onTapOutside: (_) => _commitTitle(),
                )
              : Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ),
    );

    // Long-press wraps the whole card. Skip for non-template items
    // (entries can't move through this surface — their date is the
    // source of truth) and for the fresh-card mode (the user is
    // typing; a stray long-press shouldn't yank the card away).
    if (!_isTemplate || isFresh) return card;
    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: widget.onLongPressEnd,
      onLongPressCancel: () =>
          ref.read(weekPlanDragProvider.notifier).clear(),
      child: card,
    );
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (!_isTemplate) return;
    ref.read(weekPlanDragProvider.notifier).start(
          WeekPlanDragState(
            templateId: widget.item.templateId!,
            sourceDayOfWeek: widget.weekday,
            sourceStartMinutes: widget.item.startMinutes,
            sourceEndMinutes: widget.item.endMinutes,
            pointerGlobal: details.globalPosition,
            pickupOffsetLocal: details.localPosition,
          ),
        );
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    ref
        .read(weekPlanDragProvider.notifier)
        .updatePointer(details.globalPosition);
  }
}

class _DragGhost extends StatelessWidget {
  const _DragGhost({
    required this.state,
    required this.scale,
    required this.canvasKey,
    required this.theme,
  });

  final WeekPlanDragState state;
  final WeekPlanScale scale;
  final GlobalKey canvasKey;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final box = canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return const SizedBox.shrink();
    final canvasLocal = box.globalToLocal(state.pointerGlobal);
    final ghostTop = canvasLocal.dy - state.pickupOffsetLocal.dy;

    final canvasSize = box.size;
    final ghostLeft = canvasLocal.dx - state.pickupOffsetLocal.dx;
    final ghostHeight = state.durationMinutes * _kPxPerMinute - 2;

    final altHeld = HardwareKeyboard.instance.isAltPressed;

    return Positioned(
      left: ghostLeft.clamp(0, canvasSize.width - _kDayColumnWidth),
      top: ghostTop,
      width: _kDayColumnWidth - 8,
      height: ghostHeight,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    altHeld ? 'Drop to duplicate' : 'Move…',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (altHeld)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
