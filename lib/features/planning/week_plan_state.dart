import 'package:basecamp/core/format/date.dart';
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tiny Riverpod state holders for the week plan canvas. All four
/// pieces of UI state live here so the canvas, the FAB, the header,
/// and the group-filter chip rail can stay decoupled.
///
/// `Notifier<T>` everywhere instead of `StateProvider` so the
/// callsites read intent (`.set(x)`, `.toggle()`) rather than
/// opaque `state =` assignments.

/// Monday of the visible week. Defaults to the current week's
/// Monday on init; `WeekPlanWeekNotifier.shift(±n)` advances by
/// whole weeks. Time component is always midnight local.
class WeekPlanWeekNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now().dayOnly;
    return now.subtract(Duration(days: now.weekday - 1));
  }

  void shift(int weeks) {
    state = state.add(Duration(days: 7 * weeks));
  }

  void thisWeek() {
    final now = DateTime.now().dayOnly;
    state = now.subtract(Duration(days: now.weekday - 1));
  }

  void set(DateTime monday) {
    state = monday.dayOnly;
  }
}

final weekPlanWeekProvider =
    NotifierProvider<WeekPlanWeekNotifier, DateTime>(
  WeekPlanWeekNotifier.new,
);

/// Convenience: which day-of-week the next FAB-tap "Add" lands in.
/// Updates whenever the user taps a column or interacts with a
/// card. Defaults to today's weekday when it's a weekday, Mon
/// otherwise. Range: 1..5 (Mon..Fri — Sat/Sun aren't on the canvas).
class WeekPlanFocusedDayNotifier extends Notifier<int> {
  @override
  int build() {
    final today = DateTime.now().weekday;
    return today >= 1 && today <= 5 ? today : 1;
  }

  void set(int dayOfWeek) {
    if (dayOfWeek < 1 || dayOfWeek > 5) return;
    state = dayOfWeek;
  }
}

final weekPlanFocusedDayProvider =
    NotifierProvider<WeekPlanFocusedDayNotifier, int>(
  WeekPlanFocusedDayNotifier.new,
);

/// Currently-selected card's template id, or null when nothing's
/// selected. Drives the FAB transform: null → `+` (add), non-null
/// → `✏️` (open edit sheet).
class WeekPlanSelectedNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  // Method, not a setter, because the call site reads better as
  // `notifier.select(id)` than `notifier.selected = id` — a setter
  // implies a passive write, but selection is a *user action*.
  // ignore: use_setters_to_change_properties
  void select(String templateId) {
    state = templateId;
  }

  void clear() {
    state = null;
  }
}

final weekPlanSelectedTemplateProvider =
    NotifierProvider<WeekPlanSelectedNotifier, String?>(
  WeekPlanSelectedNotifier.new,
);

/// Active group filter. Null = "All groups" view (every template
/// renders, including all-groups templates). Non-null = scope to
/// one group (renders templates for that group + all-groups
/// templates).
class WeekPlanGroupFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  // Method-not-setter for the same reason `select` above is — the
  // group-filter chip is a user choice, the call site reading
  // `.set(id)` makes that explicit.
  // ignore: use_setters_to_change_properties
  void set(String? groupId) {
    state = groupId;
  }
}

final weekPlanGroupFilterProvider =
    NotifierProvider<WeekPlanGroupFilterNotifier, String?>(
  WeekPlanGroupFilterNotifier.new,
);

/// Live drag state. Non-null only while the user is mid-long-press
/// drag of a card. Used by the canvas to render a ghost following
/// the pointer; cleared on release (which fires the immediate
/// commit).
class WeekPlanDragState {
  const WeekPlanDragState({
    required this.templateId,
    required this.sourceDayOfWeek,
    required this.sourceStartMinutes,
    required this.sourceEndMinutes,
    required this.pointerGlobal,
    required this.pickupOffsetLocal,
  });

  final String templateId;
  final int sourceDayOfWeek;
  final int sourceStartMinutes;
  final int sourceEndMinutes;

  /// Global screen position of the pointer right now. Updated on
  /// every long-press-move event.
  final Offset pointerGlobal;

  /// Where on the card the user pressed initially, in card-local
  /// coordinates. The ghost preserves this offset so the card lifts
  /// "from where the finger is" rather than snapping to the
  /// pointer's tip.
  final Offset pickupOffsetLocal;

  int get durationMinutes => sourceEndMinutes - sourceStartMinutes;

  WeekPlanDragState copyWithPointer(Offset pointer) => WeekPlanDragState(
        templateId: templateId,
        sourceDayOfWeek: sourceDayOfWeek,
        sourceStartMinutes: sourceStartMinutes,
        sourceEndMinutes: sourceEndMinutes,
        pointerGlobal: pointer,
        pickupOffsetLocal: pickupOffsetLocal,
      );
}

class WeekPlanDragNotifier extends Notifier<WeekPlanDragState?> {
  @override
  WeekPlanDragState? build() => null;

  // Method-not-setter for the same reason `select` above is —
  // starting a drag is a user action, not a property write.
  // ignore: use_setters_to_change_properties
  void start(WeekPlanDragState dragState) {
    state = dragState;
  }

  void updatePointer(Offset global) {
    final current = state;
    if (current == null) return;
    state = current.copyWithPointer(global);
  }

  void clear() {
    state = null;
  }
}

final weekPlanDragProvider =
    NotifierProvider<WeekPlanDragNotifier, WeekPlanDragState?>(
  WeekPlanDragNotifier.new,
);

/// Live edge-resize state. Non-null while the user is mid-pan on
/// a card's top or bottom edge handle. Used by the column to
/// render the card at its LIVE bounds (so it grows/shrinks in real
/// time) and by the time chips to display the live snap target.
class WeekPlanResizeState {
  const WeekPlanResizeState({
    required this.templateId,
    required this.topEdge,
    required this.sourceStartMinutes,
    required this.sourceEndMinutes,
    required this.panStartGlobalY,
    required this.liveStartMinutes,
    required this.liveEndMinutes,
  });

  final String templateId;

  /// True when the user grabbed the top edge (start changes); false
  /// for bottom edge (end changes).
  final bool topEdge;

  final int sourceStartMinutes;
  final int sourceEndMinutes;

  /// Global pointer Y at pan-start. Subtract from the current
  /// global Y to get total delta — incremental `delta.dy` would
  /// accumulate rounding errors over a long drag.
  final double panStartGlobalY;

  /// Snapped, clamped values that the column renders against.
  final int liveStartMinutes;
  final int liveEndMinutes;

  WeekPlanResizeState copyWithLive({
    int? liveStart,
    int? liveEnd,
  }) =>
      WeekPlanResizeState(
        templateId: templateId,
        topEdge: topEdge,
        sourceStartMinutes: sourceStartMinutes,
        sourceEndMinutes: sourceEndMinutes,
        panStartGlobalY: panStartGlobalY,
        liveStartMinutes: liveStart ?? liveStartMinutes,
        liveEndMinutes: liveEnd ?? liveEndMinutes,
      );
}

class WeekPlanResizeNotifier extends Notifier<WeekPlanResizeState?> {
  @override
  WeekPlanResizeState? build() => null;

  // Method-not-setter — pan-start is a user gesture, not a passive
  // property write.
  // ignore: use_setters_to_change_properties
  void start(WeekPlanResizeState s) {
    state = s;
  }

  void update({int? liveStart, int? liveEnd}) {
    final current = state;
    if (current == null) return;
    state = current.copyWithLive(
      liveStart: liveStart,
      liveEnd: liveEnd,
    );
  }

  void clear() {
    state = null;
  }
}

final weekPlanResizeProvider =
    NotifierProvider<WeekPlanResizeNotifier, WeekPlanResizeState?>(
  WeekPlanResizeNotifier.new,
);

/// Currently-hovered template id (web mouse only — touch never
/// fires hover). Drives the on-hover × delete chip so users
/// discover the action without having to select first.
class WeekPlanHoveredNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  // Method-not-setter — pointer-enter is a transient event with a
  // paired clear; setter would imply a passive write.
  // ignore: use_setters_to_change_properties
  void enter(String templateId) {
    state = templateId;
  }

  void exit(String templateId) {
    // Only clear if the leaving id is the one currently held —
    // prevents a fast hover swap (A.exit → B.enter then A.exit
    // landed late) from blanking the new hover.
    if (state == templateId) state = null;
  }
}

final weekPlanHoveredTemplateProvider =
    NotifierProvider<WeekPlanHoveredNotifier, String?>(
  WeekPlanHoveredNotifier.new,
);

/// ID of a freshly-created card whose title TextField should
/// autofocus on first build. Cleared once the user commits or
/// cancels the title input. Mirrors the empty-slot click flow:
/// click → `addTemplate` returns id → set this provider → card
/// renders with autofocused TextField → user types title → cleared.
class WeekPlanFreshCardNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  // Method-not-setter — `notifier.mark(id)` reads as a flag-setting
  // event (analogous to `select`); a setter would imply a passive
  // property write.
  // ignore: use_setters_to_change_properties
  void mark(String templateId) {
    state = templateId;
  }

  void clear() {
    state = null;
  }
}

final weekPlanFreshCardProvider =
    NotifierProvider<WeekPlanFreshCardNotifier, String?>(
  WeekPlanFreshCardNotifier.new,
);
