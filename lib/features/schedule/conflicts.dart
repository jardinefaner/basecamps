import 'package:basecamp/features/schedule/schedule_repository.dart';

/// Returns the ids of schedule items that conflict with at least one other
/// item in [items]. Two items conflict when their time ranges overlap AND
/// they share either a pod or a specialist.
Set<String> detectConflictingIds(List<ScheduleItem> items) {
  final conflicts = <String>{};
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      final a = items[i];
      final b = items[j];
      if (_overlap(a, b) && (_sharePod(a, b) || _shareSpecialist(a, b))) {
        conflicts
          ..add(a.id)
          ..add(b.id);
      }
    }
  }
  return conflicts;
}

/// For each item in [items] that conflicts with at least one other item,
/// returns the list of conflicting counterparts and why they clash. The
/// map is keyed by the item's id.
Map<String, List<ConflictInfo>> conflictsByItemId(List<ScheduleItem> items) {
  final result = <String, List<ConflictInfo>>{};
  for (var i = 0; i < items.length; i++) {
    for (var j = 0; j < items.length; j++) {
      if (i == j) continue;
      final a = items[i];
      final b = items[j];
      if (!_overlap(a, b)) continue;
      final sharedPods = _sharedPodIds(a, b);
      final podClash = sharedPods.isNotEmpty || _allPodsClash(a, b);
      final specialistClash = _shareSpecialist(a, b);
      if (!podClash && !specialistClash) continue;
      result.putIfAbsent(a.id, () => <ConflictInfo>[]).add(
            ConflictInfo(
              other: b,
              podClash: podClash,
              specialistClash: specialistClash,
              sharedPodIds: sharedPods,
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

  /// Pod ids that both activities target directly. Empty when the clash
  /// comes from one side being "all pods".
  final Set<String> sharedPodIds;
}

bool _overlap(ScheduleItem a, ScheduleItem b) {
  if (a.isFullDay || b.isFullDay) return true;
  return a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes;
}

bool _sharePod(ScheduleItem a, ScheduleItem b) {
  if (a.podIds.isEmpty || b.podIds.isEmpty) return true;
  return a.podIds.toSet().intersection(b.podIds.toSet()).isNotEmpty;
}

bool _shareSpecialist(ScheduleItem a, ScheduleItem b) {
  return a.specialistId != null && a.specialistId == b.specialistId;
}

Set<String> _sharedPodIds(ScheduleItem a, ScheduleItem b) {
  if (a.podIds.isEmpty || b.podIds.isEmpty) return const <String>{};
  return a.podIds.toSet().intersection(b.podIds.toSet());
}

bool _allPodsClash(ScheduleItem a, ScheduleItem b) {
  // One side "all pods" and the other has specific pods → every kid in
  // those pods is double-booked by the broadcast activity.
  if (a.podIds.isEmpty && b.podIds.isEmpty) return true;
  if (a.podIds.isEmpty || b.podIds.isEmpty) return true;
  return false;
}
