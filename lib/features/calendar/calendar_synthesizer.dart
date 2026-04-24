import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/calendar/calendar_event.dart';
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
  // as a flat list and we filter in Dart since the set of trips is
  // small in practice.
  final scheduleRepo = ref.watch(scheduleRepositoryProvider);
  final tripsRepo = ref.watch(tripsRepositoryProvider);

  final scheduleStream = scheduleRepo.watchScheduleForDate(day);
  final tripsStream = tripsRepo.watchAll();

  // combine-latest-2: emit a fresh synthesized list whenever either
  // upstream stream updates. Both sides default to empty until their
  // first emission; the first `emit` fires as soon as BOTH have
  // emitted at least once.
  final controller = StreamController<List<CalendarEvent>>();
  var schedule = const <ScheduleItem>[];
  var trips = const <Trip>[];
  var gotSchedule = false;
  var gotTrips = false;

  void emit() {
    if (!gotSchedule || !gotTrips) return;
    if (controller.isClosed) return;
    controller.add(
      _combineDay(date: day, schedule: schedule, trips: trips),
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
  controller.onCancel = () async {
    await sub1.cancel();
    await sub2.cancel();
  };
  ref.onDispose(() {
    unawaited(sub1.cancel());
    unawaited(sub2.cancel());
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
}) {
  final out = <CalendarEvent>[];
  for (final item in schedule) {
    out.add(calendarEventFromScheduleItem(item));
  }
  for (final trip in trips) {
    if (!_tripIntersects(trip, date)) continue;
    out.add(calendarEventFromTrip(trip));
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

/// Today's events including break/lunch windows for a specific set
/// of adults. The caller opts in by passing adult ids — typically
/// "the selected group's anchor leads" so the agenda surfaces the
/// teacher's own pod's breaks without flooding the feed with every
/// adult's status.
///
/// Parameter passed as a sorted-joined string key so the family
/// equality works the usual way. Empty = no break events (just
/// activities + trips).
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

    return baseAsync.whenData((baseEvents) {
      final adults =
          adultsAsync.asData?.value ?? const <Adult>[];
      final availability = availabilityAsync.asData?.value ??
          const <AdultAvailabilityData>[];
      if (adults.isEmpty || availability.isEmpty) {
        return baseEvents;
      }
      final adultsById = {
        for (final s in adults)
          if (adultIds.contains(s.id)) s.id: s,
      };
      if (adultsById.isEmpty) return baseEvents;

      final isoDay = today.weekday;
      final breakEvents = <CalendarEvent>[];
      for (final a in availability) {
        if (a.dayOfWeek != isoDay) continue;
        final adult = adultsById[a.adultId];
        if (adult == null) continue;
        breakEvents.addAll(
          calendarEventsFromAvailability(
            availability: a,
            adult: adult,
            date: today,
          ),
        );
      }
      if (breakEvents.isEmpty) return baseEvents;
      return <CalendarEvent>[...baseEvents, ...breakEvents]
        ..sort((a, b) {
          if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
          final byStart = a.startAt.compareTo(b.startAt);
          if (byStart != 0) return byStart;
          return a.title.compareTo(b.title);
        });
    });
  },
);
