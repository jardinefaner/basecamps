import 'package:basecamp/features/schedule/schedule_repository.dart';

/// Returns the ids of schedule items that conflict with at least one other
/// item in [items]. Two items conflict when their time ranges overlap AND
/// they share either a pod or a specialist.
///
/// - A full-day item is treated as spanning every time slot for its day.
/// - An empty [ScheduleItem.podIds] list means "all pods" — it shares pods
///   with every other item that has any pods listed (or also "all pods").
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

bool _overlap(ScheduleItem a, ScheduleItem b) {
  if (a.isFullDay || b.isFullDay) return true;
  return a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes;
}

bool _sharePod(ScheduleItem a, ScheduleItem b) {
  // "All pods" (empty list) always shares with anything non-trivial.
  if (a.podIds.isEmpty || b.podIds.isEmpty) return true;
  return a.podIds.toSet().intersection(b.podIds.toSet()).isNotEmpty;
}

bool _shareSpecialist(ScheduleItem a, ScheduleItem b) {
  return a.specialistId != null && a.specialistId == b.specialistId;
}
