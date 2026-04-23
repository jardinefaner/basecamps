import 'package:basecamp/features/schedule/schedule_repository.dart';

/// Pure bucketing logic for the Today tab — splits the day's schedule
/// items into the four groups the screen renders (current / upcoming /
/// past / all-day) based on the current wall-clock minute.
///
/// Extracted from `today_screen.dart` so the tricky edges (concurrent
/// activities, boundary minutes at start/end, multiple all-day items)
/// can be unit-tested without standing up a Flutter widget tree.
///
/// `current` is a list, not a single slot: when two activities overlap
/// right now the Today screen renders the first as the hero and the
/// rest in an "Also now" strip. Before v29 this was `ScheduleItem?`,
/// which silently dropped all but one overlapping activity.
class TodayBuckets {
  const TodayBuckets({
    required this.current,
    required this.upcoming,
    required this.past,
    required this.allDay,
  });

  /// Items whose `[start, end)` window includes `nowMinutes`. Sorted
  /// earliest-started first, title as a stable tiebreaker so the hero
  /// selection doesn't flip between minute ticks when two activities
  /// start at the same time.
  final List<ScheduleItem> current;

  /// Items that haven't started yet today. Input order preserved —
  /// the repository already returns items sorted by start time.
  final List<ScheduleItem> upcoming;

  /// Items that have already ended today.
  final List<ScheduleItem> past;

  /// All-day / full-day items. Not time-bucketed; rendered separately
  /// in the top all-day carousel.
  final List<ScheduleItem> allDay;
}

/// Buckets [items] against the current wall-clock [nowMinutes]. See
/// [TodayBuckets] for field semantics.
TodayBuckets bucketTodayItems(
  List<ScheduleItem> items,
  int nowMinutes,
) {
  final current = <ScheduleItem>[];
  final upcoming = <ScheduleItem>[];
  final past = <ScheduleItem>[];
  final allDay = <ScheduleItem>[];

  for (final item in items) {
    if (item.isFullDay) {
      allDay.add(item);
      continue;
    }
    final start = item.startMinutes;
    final end = item.endMinutes;
    // Half-open interval — an activity scheduled 10:00-11:00 is NOW at
    // 10:00, 10:59, but already "past" at exactly 11:00. Matches how
    // upcoming.first computes its countdown and how the hero picks an
    // item to render.
    if (nowMinutes >= start && nowMinutes < end) {
      current.add(item);
    } else if (nowMinutes >= end) {
      past.add(item);
    } else {
      upcoming.add(item);
    }
  }

  // Earliest-started wins the hero slot; ties broken by title so the
  // "which one is primary" choice is stable across rebuilds.
  current.sort((a, b) {
    final byStart = a.startMinutes.compareTo(b.startMinutes);
    if (byStart != 0) return byStart;
    return a.title.compareTo(b.title);
  });

  return TodayBuckets(
    current: current,
    upcoming: upcoming,
    past: past,
    allDay: allDay,
  );
}
