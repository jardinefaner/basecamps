import 'package:basecamp/features/schedule/schedule_repository.dart';

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
              podClash: res.podClash,
              specialistClash: res.specialistClash,
              sharedPodIds: _sharedPodIds(a, b),
            ),
          );
    }
  }
  return result;
}

class ConflictInfo {
  const ConflictInfo({
    required this.other,
    required this.podClash,
    required this.specialistClash,
    required this.sharedPodIds,
  });

  final ScheduleItem other;
  final bool podClash;
  final bool specialistClash;

  /// Group ids that both activities target directly. Empty when the clash
  /// comes from one side being "all groups" (broadcast).
  final Set<String> sharedPodIds;
}

/// Conflict rules, per pair of items on the same day:
///
/// - **Specialists**: if both items target the same specialist, they conflict
///   whenever their time ranges could actually overlap (a full-day item is
///   treated as covering every time slot for this rule).
/// - **Groups (timed ↔ timed)**: overlapping times + any shared group clash.
///   "All groups" (empty list) is treated as a wildcard that shares with any
///   other targeted group set.
/// - **Groups (full-day ↔ full-day)**: two whole-day events sharing groups on
///   the same date is a conflict (can't have two camp-wide events overlap).
/// - **Groups (full-day ↔ timed)**: NOT a conflict on its own. A full-day
///   label (e.g. "Tax Day", "Teacher appreciation") doesn't block timed
///   activities unless it also needs the same specialist.
_DetectionResult _detect(ScheduleItem a, ScheduleItem b) {
  final specialistClash =
      a.specialistId != null && a.specialistId == b.specialistId;
  final sharedPods = _sharePod(a, b);

  if (specialistClash) {
    final timeOverlap = _timeOverlaps(a, b);
    if (timeOverlap) {
      return _DetectionResult(
        isConflict: true,
        podClash: sharedPods && (!a.isFullDay && !b.isFullDay),
        specialistClash: true,
      );
    }
    return const _DetectionResult(
      isConflict: false,
      podClash: false,
      specialistClash: false,
    );
  }

  // No specialist overlap. Any group-based clash then requires time overlap.
  if (a.isFullDay && b.isFullDay) {
    return _DetectionResult(
      isConflict: sharedPods,
      podClash: sharedPods,
      specialistClash: false,
    );
  }
  if (a.isFullDay || b.isFullDay) {
    return const _DetectionResult(
      isConflict: false,
      podClash: false,
      specialistClash: false,
    );
  }

  // Both timed, no specialist clash.
  final timeOverlap =
      a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes;
  if (timeOverlap && sharedPods) {
    return const _DetectionResult(
      isConflict: true,
      podClash: true,
      specialistClash: false,
    );
  }
  return const _DetectionResult(
    isConflict: false,
    podClash: false,
    specialistClash: false,
  );
}

class _DetectionResult {
  const _DetectionResult({
    required this.isConflict,
    required this.podClash,
    required this.specialistClash,
  });

  final bool isConflict;
  final bool podClash;
  final bool specialistClash;
}

bool _timeOverlaps(ScheduleItem a, ScheduleItem b) {
  if (a.isFullDay || b.isFullDay) return true;
  return a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes;
}

bool _sharePod(ScheduleItem a, ScheduleItem b) {
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

Set<String> _sharedPodIds(ScheduleItem a, ScheduleItem b) {
  // No-groups activities never share with anyone (see _sharePod).
  if (a.isNoGroups || b.isNoGroups) return const <String>{};
  if (a.groupIds.isEmpty || b.groupIds.isEmpty) return const <String>{};
  return a.groupIds.toSet().intersection(b.groupIds.toSet());
}
