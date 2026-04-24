import 'package:basecamp/features/schedule/adult_shift_conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/trip_conflicts.dart';

/// Bundle of every conflict flavor we currently detect for a single
/// schedule item. Used as the value type of the map Today hands down
/// to each card so widgets can decide "is this clashing with anything
/// at all?" via [anyPresent] and render per-section reasons in the
/// conflict sheet.
///
/// All three lists are `const []` by default so callers that only
/// care about the old activity-vs-activity rules keep working
/// unchanged.
class ConflictsFor {
  const ConflictsFor({
    this.activity = const [],
    this.shift = const [],
    this.trip = const [],
  });

  final List<ConflictInfo> activity;
  final List<ShiftConflict> shift;
  final List<TripConflict> trip;

  bool get anyPresent =>
      activity.isNotEmpty || shift.isNotEmpty || trip.isNotEmpty;

  static const empty = ConflictsFor();
}

/// Returns the ids of schedule items that conflict with at least one other
/// item in [items]. See [_detect] for the rules.
Set<String> detectConflictingIds(List<ScheduleItem> items) {
  final conflicts = <String>{};
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      final res = _detect(items[i], items[j]);
      if (res.isConflict) {
        conflicts
          ..add(items[i].id)
          ..add(items[j].id);
      }
    }
  }
  return conflicts;
}

/// For each item in [items] that conflicts with at least one other item,
/// returns the counterparts and why they clash. Map keyed by item id.
Map<String, List<ConflictInfo>> conflictsByItemId(List<ScheduleItem> items) {
  final result = <String, List<ConflictInfo>>{};
  for (var i = 0; i < items.length; i++) {
    for (var j = 0; j < items.length; j++) {
      if (i == j) continue;
      final a = items[i];
      final b = items[j];
      final res = _detect(a, b);
      if (!res.isConflict) continue;
      result.putIfAbsent(a.id, () => <ConflictInfo>[]).add(
            ConflictInfo(
              other: b,
              groupClash: res.groupClash,
              adultClash: res.adultClash,
              roomClash: res.roomClash,
              sharedGroupIds: _sharedGroupIds(a, b),
            ),
          );
    }
  }
  return result;
}

class ConflictInfo {
  const ConflictInfo({
    required this.other,
    required this.groupClash,
    required this.adultClash,
    required this.roomClash,
    required this.sharedGroupIds,
  });

  final ScheduleItem other;
  final bool groupClash;
  final bool adultClash;

  /// Two activities tracked to the same [ScheduleItem.roomId] at
  /// overlapping times. Only set when both sides have a roomId — free-
  /// form location strings don't participate.
  final bool roomClash;

  /// Group ids that both activities target directly. Empty when the clash
  /// comes from one side being "all groups" (broadcast).
  final Set<String> sharedGroupIds;
}

/// Conflict rules, per pair of items on the same day:
///
/// - **Adults**: if both items target the same adult, they conflict
///   whenever their time ranges could actually overlap (a full-day item is
///   treated as covering every time slot for this rule).
/// - **Rooms**: if both items reference the same `roomId` and their time
///   ranges overlap, they conflict. Free-form location strings don't
///   participate — only tracked rooms. Off-site / trip addresses never
///   conflict.
/// - **Groups (timed ↔ timed)**: overlapping times + any shared group clash.
///   "All groups" (empty list) is treated as a wildcard that shares with any
///   other targeted group set.
/// - **Groups (full-day ↔ full-day)**: two whole-day events sharing groups on
///   the same date is a conflict (can't have two camp-wide events overlap).
/// - **Groups (full-day ↔ timed)**: NOT a conflict on its own. A full-day
///   label (e.g. "Tax Day", "Teacher appreciation") doesn't block timed
///   activities unless it also needs the same adult or room.
_DetectionResult _detect(ScheduleItem a, ScheduleItem b) {
  final adultClash =
      a.adultId != null && a.adultId == b.adultId;
  final roomClash = _roomClash(a, b);
  final sharedGroups = _shareGroup(a, b);

  // A room clash fires whenever two items are booked into the same
  // room at overlapping times — regardless of whether the groups
  // match. "Ms. Park in Art Room with Seedlings" and "Mr. Chen in
  // Art Room with Sprouts" at the same time IS a room clash even
  // though no group is shared.
  if (roomClash) {
    return _DetectionResult(
      isConflict: true,
      groupClash: sharedGroups && (!a.isFullDay && !b.isFullDay),
      adultClash: adultClash,
      roomClash: true,
    );
  }

  if (adultClash) {
    final timeOverlap = _timeOverlaps(a, b);
    if (timeOverlap) {
      return _DetectionResult(
        isConflict: true,
        groupClash: sharedGroups && (!a.isFullDay && !b.isFullDay),
        adultClash: true,
        roomClash: false,
      );
    }
    return const _DetectionResult(
      isConflict: false,
      groupClash: false,
      adultClash: false,
      roomClash: false,
    );
  }

  // No adult / room overlap. Any group-based clash then requires
  // time overlap.
  if (a.isFullDay && b.isFullDay) {
    return _DetectionResult(
      isConflict: sharedGroups,
      groupClash: sharedGroups,
      adultClash: false,
      roomClash: false,
    );
  }
  if (a.isFullDay || b.isFullDay) {
    return const _DetectionResult(
      isConflict: false,
      groupClash: false,
      adultClash: false,
      roomClash: false,
    );
  }

  // Both timed, no adult or room clash.
  final timeOverlap =
      a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes;
  if (timeOverlap && sharedGroups) {
    return const _DetectionResult(
      isConflict: true,
      groupClash: true,
      adultClash: false,
      roomClash: false,
    );
  }
  return const _DetectionResult(
    isConflict: false,
    groupClash: false,
    adultClash: false,
    roomClash: false,
  );
}

class _DetectionResult {
  const _DetectionResult({
    required this.isConflict,
    required this.groupClash,
    required this.adultClash,
    required this.roomClash,
  });

  final bool isConflict;
  final bool groupClash;
  final bool adultClash;
  final bool roomClash;
}

bool _timeOverlaps(ScheduleItem a, ScheduleItem b) {
  if (a.isFullDay || b.isFullDay) return true;
  return a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes;
}

/// Room clash = same tracked roomId + overlapping times. Free-form
/// location strings (null roomId) never trigger, even if the strings
/// happen to match — offsite / ad-hoc rooms aren't in scope.
bool _roomClash(ScheduleItem a, ScheduleItem b) {
  final aRoom = a.roomId;
  final bRoom = b.roomId;
  if (aRoom == null || bRoom == null) return false;
  if (aRoom != bRoom) return false;
  return _timeOverlaps(a, b);
}

bool _shareGroup(ScheduleItem a, ScheduleItem b) {
  // Respect the three-state audience. An intentionally-empty audience
  // (isNoGroups — teacher toggled "All groups" off and picked nothing,
  // staff prep / closure-style entries) doesn't target any children,
  // so it can't share a group with anything. Treating it as a wildcard
  // caused a spurious conflict flag to fire on every other activity
  // on the same day.
  if (a.isNoGroups || b.isNoGroups) return false;
  // Broadcast cases (allGroups=true) still act as wildcards that
  // overlap with any targeted audience on the same day.
  if (a.groupIds.isEmpty || b.groupIds.isEmpty) return true;
  return a.groupIds.toSet().intersection(b.groupIds.toSet()).isNotEmpty;
}

Set<String> _sharedGroupIds(ScheduleItem a, ScheduleItem b) {
  // No-groups activities never share with anyone (see _shareGroup).
  if (a.isNoGroups || b.isNoGroups) return const <String>{};
  if (a.groupIds.isEmpty || b.groupIds.isEmpty) return const <String>{};
  return a.groupIds.toSet().intersection(b.groupIds.toSet());
}
