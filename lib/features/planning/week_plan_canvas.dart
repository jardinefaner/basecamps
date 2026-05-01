import 'dart:async';

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
    required this.onCreateAiAt,
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

  /// Click the **+** icon on a hovered empty slot — manual create.
  /// Receives the snapped start minute + the day-of-week so the
  /// screen can `addTemplate(...)` and mark the new id as fresh-card
  /// for autofocus. Same handler as the legacy ambient slot click.
  final Future<void> Function({
    required int dayOfWeek,
    required int snappedStartMinutes,
  }) onCreateAt;

  /// Click the **✨** icon on a hovered empty slot — AI create. The
  /// screen opens the AI activity composer; on a generated result,
  /// it calls `addTemplate` with the AI's title + description + URL.
  /// Separate handler from [onCreateAt] because the screen has the
  /// context-passing scaffolding (composer, snackbars, mark-fresh)
  /// already, and bundling it would just turn this into a `kind`-
  /// switching helper.
  final Future<void> Function({
    required int dayOfWeek,
    required int snappedStartMinutes,
  }) onCreateAiAt;

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
  // GlobalKey on the inner body container so the drop handler
  // can convert global pointer coords → canvas-local for the snap
  // math. The render box reflects the live scroll transform, so
  // globalToLocal correctly accounts for both axes.
  final GlobalKey _canvasBodyKey = GlobalKey();

  // Frozen-pane scroll controllers. Day headers + hour rail mirror
  // the body's scroll position via one-way listeners (rails are
  // `NeverScrollableScrollPhysics` so the user can't double-drive
  // them; only the body accepts gestures).
  final ScrollController _vBody = ScrollController();
  final ScrollController _hBody = ScrollController();
  final ScrollController _vRail = ScrollController();
  final ScrollController _hHeader = ScrollController();

  bool _didCenterOnNow = false;
  bool _syncingV = false;
  bool _syncingH = false;

  @override
  void initState() {
    super.initState();
    // One-way mirroring: body drives the rails. Reentrancy guard
    // because while we're calling jumpTo on the rail the rail
    // emits its own update which would otherwise re-fire this
    // callback.
    _vBody.addListener(() {
      if (_syncingV || !_vRail.hasClients) return;
      _syncingV = true;
      final target = _vBody.offset.clamp(
        _vRail.position.minScrollExtent,
        _vRail.position.maxScrollExtent,
      );
      if ((target - _vRail.offset).abs() > 0.5) {
        _vRail.jumpTo(target);
      }
      _syncingV = false;
    });
    _hBody.addListener(() {
      if (_syncingH || !_hHeader.hasClients) return;
      _syncingH = true;
      final target = _hBody.offset.clamp(
        _hHeader.position.minScrollExtent,
        _hHeader.position.maxScrollExtent,
      );
      if ((target - _hHeader.offset).abs() > 0.5) {
        _hHeader.jumpTo(target);
      }
      _syncingH = false;
    });
  }

  @override
  void dispose() {
    _vBody.dispose();
    _hBody.dispose();
    _vRail.dispose();
    _hHeader.dispose();
    super.dispose();
  }

  /// Schedule a one-shot scroll-to-now after the first layout pass.
  /// Centers the current time vertically in the visible viewport so
  /// the user sees what just happened + what's coming up next.
  /// Drives `_vBody`; the rail follows via the listener.
  void _scheduleCenterOnNow(WeekPlanScale scale) {
    if (_didCenterOnNow) return;
    _didCenterOnNow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vBody.hasClients) return;
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      if (nowMinutes < scale.dayStartMinutes ||
          nowMinutes > scale.dayEndMinutes) {
        return;
      }
      // Header is frozen now (separate row), so the body's y=0
      // already corresponds to dayStartMinutes — no header
      // padding to offset.
      final nowY = scale.yFor(nowMinutes);
      final viewport = _vBody.position.viewportDimension;
      final maxScroll = _vBody.position.maxScrollExtent;
      final desired = (nowY - viewport / 2).clamp(0.0, maxScroll);
      _vBody.jumpTo(desired);
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

    const bodyWidth = _kDayColumnWidth * scheduleDayCount;
    final bodyHeight = scale.totalHeight + AppSpacing.md;

    final selectedTemplateId =
        ref.watch(weekPlanSelectedTemplateProvider);

    final canvas = GestureDetector(
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
        // Frozen-pane layout — four quadrants:
        //   ┌─────────┬───────────────────┐
        //   │ corner  │ day headers       │ ← top stripe (frozen y)
        //   ├─────────┼───────────────────┤
        //   │ hour    │ body (cards)      │ ← main body
        //   │ rail    │                   │
        //   └─────────┴───────────────────┘
        //              ↑ frozen x
        // The corner stays put; headers scroll x with the body;
        // rail scrolls y with the body; body scrolls both.
        child: Column(
          children: [
            // TOP STRIPE: corner + scrolling day headers
            SizedBox(
              height: _kColumnHeaderHeight,
              child: Row(
                children: [
                  // Empty corner square aligned with the rail.
                  const SizedBox(width: _kHourLabelWidth),
                  Expanded(
                    // Rails don't take user input — only mirror the
                    // body's scroll. ScrollConfiguration with
                    // `scrollbars: false` hides Material 3's default
                    // scrollbar that otherwise renders on every
                    // SingleChildScrollView even when physics is
                    // disabled (the user reported "scroll bar to the
                    // left of the week plan" — same shape on the
                    // headers).
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        controller: _hHeader,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: bodyWidth,
                          child: Row(
                            children: [
                              for (var d = 1; d <= scheduleDayCount; d++)
                                SizedBox(
                                  width: _kDayColumnWidth,
                                  child: _DayHeader(
                                    date: widget.monday
                                        .add(Duration(days: d - 1)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT RAIL: hour labels, follows body's vertical
                  // scroll. Same scrollbar suppression as the
                  // header strip — rails don't take user input.
                  SizedBox(
                    width: _kHourLabelWidth,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        controller: _vRail,
                        physics: const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          height: bodyHeight,
                          child: _HourGutter(scale: scale, theme: theme),
                        ),
                      ),
                    ),
                  ),
                  // BODY: 2D-scrolling card grid.
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _hBody,
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _vBody,
                        child: SizedBox(
                          key: _canvasBodyKey,
                          width: bodyWidth,
                          height: bodyHeight,
                          child: Stack(
                            children: [
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  for (var d = 1;
                                      d <= scheduleDayCount;
                                      d++)
                                    SizedBox(
                                      width: _kDayColumnWidth,
                                      child: _DayColumnBody(
                                        date: widget.monday
                                            .add(Duration(days: d - 1)),
                                        weekday: d,
                                        items: visibleByDay[d] ??
                                            const [],
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
                                          snappedStartMinutes:
                                              snappedStart,
                                        ),
                                        onCreateAiAt: (snappedStart) =>
                                            widget.onCreateAiAt(
                                          dayOfWeek: d,
                                          snappedStartMinutes:
                                              snappedStart,
                                        ),
                                        onDeleteCard: _deleteSelected,
                                      ),
                                    ),
                                ],
                              ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Delete-key shortcut. Pressing Delete (or Backspace) anywhere
    // inside the canvas while a card is selected → delete with an
    // Undo SnackBar. Wrapping in `Shortcuts` + `Actions` means the
    // shortcut only fires when focus is within the canvas; a
    // TextField (e.g. the fresh-card title input) intercepts first
    // because it's deeper in the focus tree.
    //
    // Focus is grabbed by an `onTap` (selecting a card) rather
    // than `autofocus: true` — autofocus during build was
    // triggering a Riverpod "modify provider during build"
    // exception when the canvas was rebuilt mid-stream-emit.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): _DeleteIntent(),
      },
      child: Actions(
        actions: {
          _DeleteIntent: CallbackAction<_DeleteIntent>(
            onInvoke: (_) {
              final id = selectedTemplateId;
              if (id != null) {
                unawaited(_deleteSelected(id));
              }
              return null;
            },
          ),
        },
        // Tap card or empty slot grabs focus implicitly via the
        // child's GestureDetector + a parent Focus wrapper that's
        // descendantsAreFocusable.
        child: Focus(canRequestFocus: true, child: canvas),
      ),
    );
  }

  /// Delete the selected template, surface an Undo SnackBar, and
  /// clear the selection. Re-creates the row on Undo via
  /// `addTemplate` with the same payload.
  Future<void> _deleteSelected(String templateId) async {
    final repo = ref.read(scheduleRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final template = await repo.getTemplate(templateId);
    if (template == null || !mounted) return;
    await repo.deleteTemplate(templateId);
    ref.read(weekPlanSelectedTemplateProvider.notifier).clear();
    if (!mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${template.title}".'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await repo.addTemplate(
                dayOfWeek: template.dayOfWeek,
                startTime: template.startTime,
                endTime: template.endTime,
                title: template.title,
                allGroups: template.allGroups,
                adultId: template.adultId,
                location: template.location,
                notes: template.notes,
                startDate: template.startDate,
                endDate: template.endDate,
                isFullDay: template.isFullDay,
              );
            },
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
/// hour. The ticks line up with each [_DayColumnBody]'s grid
/// lines.
class _HourGutter extends StatelessWidget {
  const _HourGutter({required this.scale, required this.theme});

  final WeekPlanScale scale;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hourCount = ((scale.totalMinutes + 59) / 60).floor();
    // No top padding — the rail is now in its own row, parallel
    // to the body. Day headers live in a separate frozen stripe
    // above.
    return SizedBox(
      width: _kHourLabelWidth,
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
    );
  }
}

/// Intent for the Delete-key shortcut on the canvas. Wired in
/// `WeekPlanCanvas.build` via `Shortcuts` + `Actions`.
class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

/// Frozen day-header cell. Lives in the top stripe (separate from
/// the column body) so it stays put while the body scrolls
/// vertically. Mon–Fri abbrev + day number; today highlights.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat.E().format(date).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: _isToday
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
              fontWeight: _isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            DateFormat.d().format(date),
            style: theme.textTheme.titleMedium?.copyWith(
              color: _isToday
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
              fontWeight: _isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayColumnBody extends ConsumerStatefulWidget {
  const _DayColumnBody({
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
    required this.onCreateAiAt,
    required this.onDeleteCard,
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
  // AI-create variant. Same shape as onCreateAt — the parent screen
  // owns the composer-opening + addTemplate-with-AI-fields flow; the
  // column just plumbs the snapped slot through.
  final Future<void> Function(int snappedStartMinutes) onCreateAiAt;
  final Future<void> Function(String templateId) onDeleteCard;

  @override
  ConsumerState<_DayColumnBody> createState() => _DayColumnBodyState();
}

class _DayColumnBodyState extends ConsumerState<_DayColumnBody> {
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
    final scale = widget.scale;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
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
                  // Empty-slot hover layer. Sits BELOW the cards so
                  // card hits beat empty-slot hits — the hover
                  // detector only fires on the gaps between cards.
                  // Tap-to-create is no longer ambient — the user
                  // explicitly clicks one of the slot icons (manual
                  // / AI) layered above this. That makes the choice
                  // discoverable and prevents an accidental ambient
                  // click from creating a blank card when the user
                  // really wanted the AI path.
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
                      // Opaque hit-testing so this layer absorbs
                      // pointer events that would otherwise fall
                      // through to whatever's underneath. The slot
                      // icons are layered on top in their own
                      // Positioned, so they receive the click.
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // Hovered-slot outline. Painted over the hover
                  // layer so it stays readable even when the cursor
                  // moves fast. IgnorePointer so it doesn't steal
                  // taps from the slot-icons layer above.
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
                  // Slot action icons — manual + AI. Anchored to the
                  // right edge of the hovered slot. Each icon has
                  // its own InkWell that consumes the tap so the
                  // hover layer below never sees it.
                  if (_hoveredSlotStart != null)
                    Positioned(
                      top: scale.yFor(_hoveredSlotStart!),
                      right: 6,
                      height: 15 * _kPxPerMinute,
                      child: _SlotActionIcons(
                        onManual: () =>
                            widget.onCreateAt(_hoveredSlotStart!),
                        onAi: () =>
                            widget.onCreateAiAt(_hoveredSlotStart!),
                      ),
                    ),
                  // The cards. Hidden when this card is the drag
                  // source (the ghost overlay paints in its place).
                  // When the card is being live-resized via an edge
                  // handle, render at the live bounds so the user
                  // sees the new size immediately.
                  for (final item in widget.items)
                    if (!item.isFullDay)
                      _positionedCard(item, scale),
                  // Selected-card time chips. Top-left = start;
                  // bottom-left = end. Painted outside the card via
                  // negative offsets (clipBehavior: Clip.none on the
                  // body Stack so this works). Chip values reflect
                  // the live-resize state when active so the user
                  // sees the snap target update in real time.
          for (final item in widget.items)
            if (item.templateId != null &&
                item.templateId == widget.selectedId)
              ..._buildTimeChips(item, scale, theme),
          // × delete chip — visibility depends on hover OR
          // selection so web mouse users discover it on hover and
          // touch users still see it on tap.
          ..._buildDeleteChips(scale, theme),
        ],
      ),
    ),
    );
  }

  /// Collects the (at most one) delete chip across all items.
  /// Returns the empty list when nothing's hovered or selected so
  /// the spread doesn't pollute the Stack with empties.
  List<Widget> _buildDeleteChips(
    WeekPlanScale scale,
    ThemeData theme,
  ) {
    final hoveredId = ref.watch(weekPlanHoveredTemplateProvider);
    final out = <Widget>[];
    for (final item in widget.items) {
      final chip = _buildDeleteChip(item, scale, theme, hoveredId);
      if (chip != null) out.add(chip);
    }
    return out;
  }

  /// Compute the (start, end) bounds the column should render this
  /// item at. Live-resize state (when matching this template id)
  /// overrides the row's persisted values.
  ({int start, int end}) _liveBounds(ScheduleItem item) {
    final resize = ref.watch(weekPlanResizeProvider);
    if (resize != null && resize.templateId == item.templateId) {
      return (start: resize.liveStartMinutes, end: resize.liveEndMinutes);
    }
    return (start: item.startMinutes, end: item.endMinutes);
  }

  Widget _positionedCard(ScheduleItem item, WeekPlanScale scale) {
    final bounds = _liveBounds(item);
    final isResizingThis = ref
            .watch(weekPlanResizeProvider)
            ?.templateId ==
        item.templateId;
    return Positioned(
      top: scale.yFor(bounds.start),
      left: 4,
      right: 4,
      height: (bounds.end - bounds.start) * _kPxPerMinute - 2,
      child: Opacity(
        opacity: widget.dragState?.templateId == item.templateId
            ? 0.25
            : 1,
        child: _PlanCard(
          item: item,
          weekday: widget.weekday,
          isSelected: item.templateId != null &&
              item.templateId == widget.selectedId,
          isResizingNow: isResizingThis,
          onTap: widget.onTapCard,
          onTapAlreadySelected: widget.onTapAlreadySelected,
          onLongPressEnd: widget.onLongPressEnd,
        ),
      ),
    );
  }

  /// Render the start + end time chips for a selected card. Each
  /// is anchored *outside* the card via negative offsets — start
  /// pokes above the top-LEFT, end below the bottom-LEFT. Compact
  /// "9:00a" format so they read fast. Live-resize bounds drive
  /// the labels so the snap target ticks by during the drag.
  ///
  /// The × delete chip is rendered separately by `_buildDeleteChip`
  /// because its visibility rule (hover OR selected) differs from
  /// the time chips (selected only).
  List<Widget> _buildTimeChips(
    ScheduleItem item,
    WeekPlanScale scale,
    ThemeData theme,
  ) {
    final bounds = _liveBounds(item);
    return [
      Positioned(
        top: scale.yFor(bounds.start) - 14,
        left: 4,
        child: _TimeChip(
          label: Hhmm.fromMinutes(bounds.start)._asCompact(),
          theme: theme,
        ),
      ),
      Positioned(
        top: scale.yFor(bounds.end) - 6,
        left: 4,
        child: _TimeChip(
          label: Hhmm.fromMinutes(bounds.end)._asCompact(),
          theme: theme,
        ),
      ),
    ];
  }

  /// Floating × delete chip, top-right exterior of the card.
  /// Visible when the card is hovered (web mouse) OR selected
  /// (touch fallback, since hover doesn't fire there). Returns
  /// `null` if the item isn't a template-backed card or the
  /// affordance shouldn't show.
  Widget? _buildDeleteChip(
    ScheduleItem item,
    WeekPlanScale scale,
    ThemeData theme,
    String? hoveredId,
  ) {
    final templateId = item.templateId;
    if (templateId == null) return null;
    final visible = templateId == hoveredId ||
        templateId == widget.selectedId;
    if (!visible) return null;
    final bounds = _liveBounds(item);
    return Positioned(
      top: scale.yFor(bounds.start) - 14,
      right: 4,
      child: _DeleteChip(
        onTap: () => unawaited(widget.onDeleteCard(templateId)),
        theme: theme,
      ),
    );
  }
}

extension _CompactTime on String {
  /// Compact-format an "HH:mm" string. Tiny adapter so the chips
  /// can take a wire-format time and emit "9:00a" without a
  /// caller-side conversion. (`Hhmm.formatCompact` already does
  /// exactly this on the static class.)
  String _asCompact() => Hhmm.formatCompact(this);
}

/// Two-icon row that anchors to the right edge of the hovered empty
/// slot. The user picks the create path explicitly:
///   * `+` (manual) → existing zero-friction blank-card flow
///   * `✨` (AI)    → opens the shared AI activity composer
///
/// Each icon is a small circular tap target sized to fit a 15-min
/// slot (37.5 px tall). InkWells consume their taps so the hover
/// layer below them never fires.
class _SlotActionIcons extends StatelessWidget {
  const _SlotActionIcons({required this.onManual, required this.onAi});

  final VoidCallback onManual;
  final VoidCallback onAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SlotIconButton(
            icon: Icons.add,
            tooltip: 'New activity',
            onTap: onManual,
            background: theme.colorScheme.surface,
            foreground: theme.colorScheme.onSurface,
            borderColor: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(width: 4),
          _SlotIconButton(
            icon: Icons.auto_awesome_outlined,
            tooltip: 'AI activity',
            onTap: onAi,
            // Tinted so the AI option reads as a distinct affordance
            // — the manual + is grey-on-surface, the AI ✨ is
            // primary-on-primary-container.
            background: theme.colorScheme.primaryContainer,
            foreground: theme.colorScheme.onPrimaryContainer,
            borderColor: theme.colorScheme.primary
                .withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _SlotIconButton extends StatelessWidget {
  const _SlotIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.borderColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final Color borderColor;

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_size / 2),
          side: BorderSide(color: borderColor, width: 0.5),
        ),
        child: InkWell(
          // BorderRadius matches the Material so the hover splash
          // doesn't bleed past the circle.
          borderRadius: BorderRadius.circular(_size / 2),
          onTap: onTap,
          child: SizedBox(
            width: _size,
            height: _size,
            child: Icon(icon, size: 16, color: foreground),
          ),
        ),
      ),
    );
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
    required this.isResizingNow,
    required this.onTap,
    required this.onTapAlreadySelected,
    required this.onLongPressEnd,
  });

  final ScheduleItem item;
  final int weekday;
  final bool isSelected;
  final bool isResizingNow;
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

    // Border-only selection — fill stays neutral so selecting a
    // card doesn't redraw its title, only its outline. Cleaner
    // visual: the border carries the entire selected-state signal.
    final isSelected = widget.isSelected;
    final cardColor = theme.colorScheme.surfaceContainerHigh;
    final fg = theme.colorScheme.onSurface;
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
              // The fresh-card TextField is tuned to render
              // identically to the displayed Text so committing
              // doesn't cause a layout shift:
              //   * `maxLines: 2` matches the Text's `maxLines: 2`
              //     so a long title wraps the same way before and
              //     after commit.
              //   * `InputDecoration.collapsed` strips ALL chrome
              //     (no internal padding, no border, no helper
              //     text) — the field renders flush like a plain
              //     Text node.
              //   * `textAlignVertical: TextAlignVertical.top`
              //     pins to the top edge instead of TextField's
              //     default centered baseline.
              //   * `cursorHeight` set to the font's line-height
              //     so the cursor doesn't visually push baseline.
              ? TextField(
                  controller: _titleController,
                  focusNode: _titleFocus,
                  autofocus: true,
                  maxLines: 2,
                  textAlignVertical: TextAlignVertical.top,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: fg,
                  cursorWidth: 1.5,
                  cursorHeight: theme.textTheme.titleSmall?.fontSize,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Activity name…',
                    hintStyle: theme.textTheme.titleSmall?.copyWith(
                      color: fg.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
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

    // MouseRegion publishes the hovered template id so the parent
    // column can paint the × delete chip. Touch never fires
    // hover, so touch users still get the × on selection (handled
    // by the column's chip-render condition).
    final templateId = widget.item.templateId!;

    // Stack the card body underneath two thin edge-resize handles.
    // The handles only intercept gestures inside their 8dp strip
    // — the rest of the card stays interactive for long-press
    // drag + tap-to-select.
    return MouseRegion(
      onEnter: (_) => ref
          .read(weekPlanHoveredTemplateProvider.notifier)
          .enter(templateId),
      onExit: (_) => ref
          .read(weekPlanHoveredTemplateProvider.notifier)
          .exit(templateId),
      child: GestureDetector(
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: widget.onLongPressEnd,
        onLongPressCancel: () =>
            ref.read(weekPlanDragProvider.notifier).clear(),
        child: Stack(
          children: [
            Positioned.fill(child: card),
          // Top edge — drag to change start time.
          Positioned(
            top: 0,
            left: 8,
            right: 8,
            height: 8,
            child: _EdgeHandle(
              isTop: true,
              isVisible: widget.isSelected || widget.isResizingNow,
              onPanStart: (details) =>
                  _onEdgeStart(details, topEdge: true),
              onPanUpdate: _onEdgeUpdate,
              onPanEnd: (_) => _onEdgeEnd(),
              onPanCancel: _onEdgeEnd,
            ),
          ),
          // Bottom edge — drag to change end time.
          Positioned(
            bottom: 0,
            left: 8,
            right: 8,
            height: 8,
            child: _EdgeHandle(
              isTop: false,
              isVisible: widget.isSelected || widget.isResizingNow,
              onPanStart: (details) =>
                  _onEdgeStart(details, topEdge: false),
              onPanUpdate: _onEdgeUpdate,
              onPanEnd: (_) => _onEdgeEnd(),
              onPanCancel: _onEdgeEnd,
            ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pan-start on either edge handle. Captures the pan-start
  /// global Y and original times in the resize provider.
  void _onEdgeStart(
    DragStartDetails details, {
    required bool topEdge,
  }) {
    if (!_isTemplate) return;
    // Selecting the card on resize-start so the user gets the
    // chip overlay during the drag — visual confirmation of the
    // live snap target.
    ref
        .read(weekPlanSelectedTemplateProvider.notifier)
        .select(widget.item.templateId!);
    ref.read(weekPlanResizeProvider.notifier).start(
          WeekPlanResizeState(
            templateId: widget.item.templateId!,
            topEdge: topEdge,
            sourceStartMinutes: widget.item.startMinutes,
            sourceEndMinutes: widget.item.endMinutes,
            panStartGlobalY: details.globalPosition.dy,
            liveStartMinutes: widget.item.startMinutes,
            liveEndMinutes: widget.item.endMinutes,
          ),
        );
  }

  /// Pan-update — translates total Y delta from start into
  /// snapped 15-min times, clamped so neither edge crosses the
  /// other.
  void _onEdgeUpdate(DragUpdateDetails details) {
    final state = ref.read(weekPlanResizeProvider);
    if (state == null) return;
    final totalDeltaY = details.globalPosition.dy - state.panStartGlobalY;
    final deltaMinutes = (totalDeltaY / _kPxPerMinute).round();
    if (state.topEdge) {
      // Move start time. Clamp so start ≤ end - 15 (always at
      // least one snap unit).
      var newStart = state.sourceStartMinutes + deltaMinutes;
      newStart = (newStart / 15).round() * 15;
      newStart = newStart.clamp(0, state.sourceEndMinutes - 15);
      if (newStart != state.liveStartMinutes) {
        ref
            .read(weekPlanResizeProvider.notifier)
            .update(liveStart: newStart);
      }
    } else {
      var newEnd = state.sourceEndMinutes + deltaMinutes;
      newEnd = (newEnd / 15).round() * 15;
      newEnd = newEnd.clamp(state.sourceStartMinutes + 15, 24 * 60 - 1);
      if (newEnd != state.liveEndMinutes) {
        ref
            .read(weekPlanResizeProvider.notifier)
            .update(liveEnd: newEnd);
      }
    }
  }

  /// Pan-end / pan-cancel. Commits the live values to the row if
  /// they actually changed; clears the resize provider.
  Future<void> _onEdgeEnd() async {
    final state = ref.read(weekPlanResizeProvider);
    ref.read(weekPlanResizeProvider.notifier).clear();
    if (state == null) return;
    final changed = state.liveStartMinutes != state.sourceStartMinutes ||
        state.liveEndMinutes != state.sourceEndMinutes;
    if (!changed) return;
    final repo = ref.read(scheduleRepositoryProvider);
    await repo.shiftTemplateStart(
      templateId: state.templateId,
      newStartTime: Hhmm.fromMinutes(state.liveStartMinutes),
      newEndTime: Hhmm.fromMinutes(state.liveEndMinutes),
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

/// Thin (8dp) edge-resize handle. Sits on the top or bottom of a
/// card; on web shows a `resizeUpDown` cursor on hover; gestures
/// drive the resize provider via callbacks. Handles only render a
/// visible affordance when the card is selected or actively
/// resizing — they're invisible otherwise so the cards don't look
/// busy at rest, but the gesture still works (cursor changes on
/// hover so power users discover the affordance).
class _EdgeHandle extends StatelessWidget {
  const _EdgeHandle({
    required this.isTop,
    required this.isVisible,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });

  final bool isTop;
  final bool isVisible;
  final void Function(DragStartDetails) onPanStart;
  final void Function(DragUpdateDetails) onPanUpdate;
  final void Function(DragEndDetails) onPanEnd;
  final VoidCallback onPanCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        onPanCancel: onPanCancel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: isVisible ? 1 : 0,
          child: Align(
            alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 1),
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small × button floating outside the selected card's top-right
/// corner. Discoverable replacement for the Delete-key shortcut on
/// web — a visible affordance the user finds without having to
/// know a keyboard combo. Tap fires the same delete-with-undo
/// flow as the Delete key.
class _DeleteChip extends StatelessWidget {
  const _DeleteChip({required this.onTap, required this.theme});

  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.colorScheme.errorContainer,
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: 'Delete activity',
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.close,
              size: 14,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}
