import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/calendar/calendar_event.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/trips/trips_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Synthesizer over the day's events — activities, trips, and
/// optional per-adult break/lunch windows — into one chronologically
/// sorted [CalendarEvent] stream. Keeps source tables as-is; this is
/// a READ layer so each surface (agenda view, conflict detector,
/// future calendar grids) consumes one shape.
///
/// Two providers expose this:
///   - `calendarEventsForDayProvider` — date-scoped, doesn't
///     include breaks/lunches. Drives agenda mode on Today and
///     future calendar grids.
///   - `calendarEventsWithBreaksTodayProvider` — today's events
///     PLUS breaks/lunches for the adults whose ids the caller
///     opts into (typically the selected group's anchor leads,
///     so the agenda shows "Mike on break 10:30-10:45" in the
///     teacher's focused view but not 10 other adults' breaks).

/// All activity + trip events on `date`, sorted by start time.
/// Excludes staff breaks/lunches by design — those flood the feed
/// when unfiltered, and the agenda view opts into a narrow set.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final calendarEventsForDayProvider =
    StreamProvider.family<List<CalendarEvent>, DateTime>((ref, date) {
  // Normalize to date-only — the family key is the date, not an
  // instant, so two callers with different times-of-day share one
  // subscription.
  final day = DateTime(date.year, date.month, date.day);

  // Upstream streams. Schedule is already date-scoped; trips come
  // as a flat list (and trip_groups as a flat id→ids map) — both
  // filter in Dart since the set of trips is small in practice.
  final scheduleRepo = ref.watch(scheduleRepositoryProvider);
  final tripsRepo = ref.watch(tripsRepositoryProvider);

  final scheduleStream = scheduleRepo.watchScheduleForDate(day);
  final tripsStream = tripsRepo.watchAll();
  final tripGroupsStream = tripsRepo.watchAllGroupsByTrip();

  // combine-latest-3: emit a fresh synthesized list whenever any
  // upstream stream updates. Each side defaults to empty until its
  // first emission; the first `emit` fires as soon as ALL three have
  // emitted at least once.
  final controller = StreamController<List<CalendarEvent>>();
  var schedule = const <ScheduleItem>[];
  var trips = const <Trip>[];
  var groupsByTrip = const <String, List<String>>{};
  var gotSchedule = false;
  var gotTrips = false;
  var gotTripGroups = false;

  void emit() {
    if (!gotSchedule || !gotTrips || !gotTripGroups) return;
    if (controller.isClosed) return;
    controller.add(
      _combineDay(
        date: day,
        schedule: schedule,
        trips: trips,
        groupsByTrip: groupsByTrip,
      ),
    );
  }

  final sub1 = scheduleStream.listen(
    (s) {
      schedule = s;
      gotSchedule = true;
      emit();
    },
    onError: controller.addError,
  );
  final sub2 = tripsStream.listen(
    (t) {
      trips = t;
      gotTrips = true;
      emit();
    },
    onError: controller.addError,
  );
  final sub3 = tripGroupsStream.listen(
    (m) {
      groupsByTrip = m;
      gotTripGroups = true;
      emit();
    },
    onError: controller.addError,
  );
  controller.onCancel = () async {
    await sub1.cancel();
    await sub2.cancel();
    await sub3.cancel();
  };
  ref.onDispose(() {
    unawaited(sub1.cancel());
    unawaited(sub2.cancel());
    unawaited(sub3.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});

/// Pure combine — produces the sorted event list for [date] from the
/// latest schedule + trips snapshots. Isolated so it's trivially
/// testable without standing up the stream machinery.
List<CalendarEvent> _combineDay({
  required DateTime date,
  required List<ScheduleItem> schedule,
  required List<Trip> trips,
  required Map<String, List<String>> groupsByTrip,
}) {
  final out = <CalendarEvent>[];
  // Skip schedule entries that mirror a trip — every trip writes a
  // `schedule_entries` row with `source_trip_id` set so it appears
  // in the schedule editor / week view, but the today agenda
  // already renders trips from the trips list directly. Without
  // this filter the agenda double-rendered every trip: once as a
  // proper trip card (taps → trip detail) and once as an
  // activity-style card from the mirror (taps → activity detail
  // sheet — what the user called "the editing bottom sheet").
  // Keep the trip card (the rich one); drop the mirror.
  for (final item in schedule) {
    if (item.sourceTripId != null) continue;
    out.add(calendarEventFromScheduleItem(item));
  }
  for (final trip in trips) {
    if (!_tripIntersects(trip, date)) continue;
    out.add(
      calendarEventFromTrip(
        trip,
        groupIds: groupsByTrip[trip.id] ?? const [],
      ),
    );
  }
  // Stable chronological sort: all-day first (they float above the
  // timed items in the agenda), then by start time, with a
  // title tiebreak so the order doesn't jiggle between rebuilds.
  out.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final byStart = a.startAt.compareTo(b.startAt);
    if (byStart != 0) return byStart;
    return a.title.compareTo(b.title);
  });
  return out;
}

bool _tripIntersects(Trip trip, DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final start = DateTime(trip.date.year, trip.date.month, trip.date.day);
  final end = trip.endDate == null
      ? start
      : DateTime(
          trip.endDate!.year,
          trip.endDate!.month,
          trip.endDate!.day,
        );
  return !day.isBefore(start) && !day.isAfter(end);
}

/// Today's events including break/lunch windows AND role-block
/// transitions for a specific set of adults. The caller opts in by
/// passing adult ids — typically "the selected group's anchor leads"
/// so the agenda surfaces the teacher's own pod's breaks + "Sarah →
/// specialist 11–12" role changes without flooding the feed with
/// every adult's status.
///
/// Role blocks (lead / specialist) ride the same opt-in as breaks:
/// one axis of "adults I care about" drives both. Lead blocks carry
/// their anchored group's id through so today_agenda's group-scope
/// filter keeps them pinned to the right group; specialist blocks
/// come through un-scoped and show for every group.
///
/// Parameter passed as a sorted-joined string key so the family
/// equality works the usual way. Empty = no break events and no
/// role-block events (just activities + trips).
// ignore: specify_nonobvious_property_types
final calendarEventsWithBreaksTodayProvider =
    Provider.family<AsyncValue<List<CalendarEvent>>, String>(
  (ref, adultIdsKey) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final baseAsync = ref.watch(calendarEventsForDayProvider(today));
    if (adultIdsKey.isEmpty) return baseAsync;

    final adultIds = adultIdsKey.split(',');
    final adultsAsync = ref.watch(adultsProvider);
    final availabilityAsync = ref.watch(allAvailabilityProvider);
    // Role-block side-channel. We watch the flat today-blocks stream
    // (same one the staffing + group cards use) and filter in
    // memory — the set is small (one block per adult per segment of
    // day) so a pass is cheap and avoids introducing a new family
    // parametrized on adultIds.
    final blocksAsync = ref.watch(todayAdultBlocksProvider);
    // Groups for name lookup when titling lead-block events. Missing
    // groups → the adapter falls back to "Sarah → lead" without the
    // group label.
    final groupsAsync = ref.watch(groupsProvider);

    return baseAsync.whenData((baseEvents) {
      final adults =
          adultsAsync.asData?.value ?? const <Adult>[];
      final availability = availabilityAsync.asData?.value ??
          const <AdultAvailabilityData>[];
      final blocks =
          blocksAsync.asData?.value ?? const <AdultDayBlock>[];
      final groups = groupsAsync.asData?.value ?? const <Group>[];
      if (adults.isEmpty) return baseEvents;

      final adultsById = {
        for (final s in adults)
          if (adultIds.contains(s.id)) s.id: s,
      };
      if (adultsById.isEmpty) return baseEvents;

      final groupNameById = {for (final g in groups) g.id: g.name};
      String lookupGroupName(String id) => groupNameById[id] ?? '';

      final isoDay = today.weekday;
      final extras = <CalendarEvent>[];

      // Break / lunch events.
      for (final a in availability) {
        if (a.dayOfWeek != isoDay) continue;
        final adult = adultsById[a.adultId];
        if (adult == null) continue;
        extras.addAll(
          calendarEventsFromAvailability(
            availability: a,
            adult: adult,
            date: today,
          ),
        );
      }

      // Role-block events — one per AdultDayBlock for each opted-in
      // adult. Bucket by adult so we can pass per-adult block lists
      // into the adapter (which takes a List + an Adult).
      if (blocks.isNotEmpty) {
        final byAdult = <String, List<AdultDayBlock>>{};
        for (final b in blocks) {
          if (!adultsById.containsKey(b.adultId)) continue;
          byAdult.putIfAbsent(b.adultId, () => []).add(b);
        }
        for (final entry in byAdult.entries) {
          final adult = adultsById[entry.key]!;
          extras.addAll(
            calendarEventsFromAdultBlocks(
              blocks: entry.value,
              adult: adult,
              groupNameLookup: lookupGroupName,
              date: today,
            ),
          );
        }
      }

      if (extras.isEmpty) return baseEvents;
      return <CalendarEvent>[...baseEvents, ...extras]
        ..sort((a, b) {
          if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
          final byStart = a.startAt.compareTo(b.startAt);
          if (byStart != 0) return byStart;
          return a.title.compareTo(b.title);
        });
    });
  },
);
