import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';

/// What kind of thing a calendar event represents. Drives rendering
/// (icon, tint) + dispatch on tap — each kind knows how to open its
/// source editor. Stays a narrow enum; new event types are new
/// constants + a new adapter in the synthesizer.
enum CalendarEventKind {
  /// Scheduled activity — template expansion or a one-off entry.
  /// The common case on Today.
  activity,

  /// Off-site field trip. Spans a day (or more) with optional
  /// departure / return times.
  trip,

  /// Adult availability break (morning or afternoon). Present in
  /// the agenda stream only when the caller opts in — the
  /// synthesizer filters to breaks for a set of adults (typically
  /// the selected group's anchor leads).
  adultBreak,

  /// Adult availability lunch. Same opt-in semantics as break.
  adultLunch,
}

/// One row in the chronological Today / calendar feed. Built by the
/// synthesizer from whatever source row fits — ScheduleItem, Trip,
/// AdultAvailabilityData's break/lunch windows. Consumers
/// render by kind, dispatch taps back to the right editor via
/// [sourceKind] + [sourceId].
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.sourceKind,
    required this.sourceId,
    this.groupIds = const [],
    this.allGroups = false,
    this.adultId,
    this.roomId,
    this.location,
    this.colorHex,
    this.subtitle,
  });

  /// Stable id for the rendered event — sourceKind + sourceId
  /// normalized. Used as a Flutter widget key and for de-dup; not
  /// persisted anywhere.
  final String id;

  final CalendarEventKind kind;
  final String title;

  /// Absolute start / end moments. All-day events have
  /// startAt = midnight-of-date, endAt = start of next day.
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;

  /// Groups the event is scoped to. Empty + [allGroups] true means
  /// "for everyone"; empty + [allGroups] false means "staff-only /
  /// no-groups."
  final List<String> groupIds;
  final bool allGroups;

  final String? adultId;
  final String? roomId;
  final String? location;

  /// Optional tint hint — group's color for group-scoped activities,
  /// left null for program-wide items where the group chip row
  /// already carries the tint.
  final String? colorHex;

  /// Secondary line for rendering — "Sarah · Art Room" style.
  final String? subtitle;

  /// Back-pointer to the original row. Kind tells the agenda renderer
  /// which editor to open; id tells which row.
  final String sourceKind; // 'template' | 'entry' | 'trip' | 'break' | 'lunch'
  final String sourceId;

  /// Duration in minutes — handy for renderers that show
  /// "ends in N min." Clamped to zero for all-day items where
  /// "duration" isn't meaningful.
  int get durationMinutes {
    if (allDay) return 0;
    return endAt.difference(startAt).inMinutes.clamp(0, 24 * 60);
  }
}

/// Adapter: ScheduleItem → CalendarEvent. ScheduleItem is already
/// the synthesized form of template + entry rows per date, so one
/// ScheduleItem maps to exactly one CalendarEvent.
CalendarEvent calendarEventFromScheduleItem(ScheduleItem item) {
  // Build absolute DateTimes by combining the item's date with its
  // HH:mm wire-format times. Full-day items span midnight-to-
  // midnight for sorting.
  final day = DateTime(item.date.year, item.date.month, item.date.day);
  DateTime parse(String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  final startAt = item.isFullDay ? day : parse(item.startTime);
  final endAt = item.isFullDay
      ? day.add(const Duration(days: 1))
      : parse(item.endTime);

  // Subtitle weaves adult + location just enough that the
  // agenda row reads useful without the consumer having to fetch
  // anything else.
  final parts = <String>[];
  if (item.location != null && item.location!.trim().isNotEmpty) {
    parts.add(item.location!.trim());
  }
  final subtitle = parts.isEmpty ? null : parts.join(' · ');

  // Source provenance: prefer entryId when present (one-off),
  // otherwise templateId (recurring). ScheduleItem guarantees at
  // least one is set.
  final isEntry = item.entryId != null;
  final sourceKind = isEntry ? 'entry' : 'template';
  final sourceId = isEntry ? item.entryId! : (item.templateId ?? item.id);

  return CalendarEvent(
    id: 'activity:$sourceKind:$sourceId:${item.date.toIso8601String()}',
    kind: CalendarEventKind.activity,
    title: item.title,
    startAt: startAt,
    endAt: endAt,
    allDay: item.isFullDay,
    groupIds: item.groupIds,
    allGroups: item.allGroups,
    adultId: item.adultId,
    roomId: item.roomId,
    location: item.location,
    subtitle: subtitle,
    sourceKind: sourceKind,
    sourceId: sourceId,
  );
}

/// Adapter: Trip row → CalendarEvent. A trip with no departure /
/// return times is treated as all-day for the date span.
/// Multi-day trips clamp to a single event covering the full range
/// (teachers can drill into the trip detail to see per-day
/// specifics).
///
/// [groupIds] are the groups the trip is scoped to (from trip_groups).
/// Empty list means "no scoping info" — the agenda treats those as
/// program-wide for filtering. The synthesizer supplies this by
/// looking up the trip's join rows.
CalendarEvent calendarEventFromTrip(
  Trip trip, {
  List<String> groupIds = const [],
}) {
  final startDay = DateTime(
    trip.date.year,
    trip.date.month,
    trip.date.day,
  );
  final endDay = trip.endDate == null
      ? startDay.add(const Duration(days: 1))
      : DateTime(
          trip.endDate!.year,
          trip.endDate!.month,
          trip.endDate!.day,
        ).add(const Duration(days: 1));

  final hasTimes =
      trip.departureTime != null && trip.returnTime != null;

  DateTime withTime(String hhmm, DateTime day) {
    final parts = hhmm.split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  final startAt = hasTimes
      ? withTime(trip.departureTime!, startDay)
      : startDay;
  final endAt = hasTimes
      ? withTime(trip.returnTime!, startDay)
      : endDay;

  return CalendarEvent(
    id: 'trip:${trip.id}',
    kind: CalendarEventKind.trip,
    title: trip.name,
    startAt: startAt,
    endAt: endAt,
    allDay: !hasTimes,
    groupIds: groupIds,
    // Empty trip_groups is legacy data (pre-group-scoping); treat as
    // program-wide so the agenda keeps surfacing them in every
    // group's view.
    allGroups: groupIds.isEmpty,
    location: trip.location,
    subtitle: trip.location,
    sourceKind: 'trip',
    sourceId: trip.id,
  );
}

/// Adapter: break or lunch window on AdultAvailability →
/// CalendarEvent(s). Returns 0–2 events: the main break window, an
/// optional second break (schema v35), and the lunch window.
/// [date] + [adult] come from the caller so IDs and source back-
/// pointers are unambiguous.
Iterable<CalendarEvent> calendarEventsFromAvailability({
  required AdultAvailabilityData availability,
  required Adult adult,
  required DateTime date,
}) sync* {
  final day = DateTime(date.year, date.month, date.day);
  DateTime parse(String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  if (availability.breakStart != null && availability.breakEnd != null) {
    yield CalendarEvent(
      id: 'break:${adult.id}:${day.millisecondsSinceEpoch}',
      kind: CalendarEventKind.adultBreak,
      title: '${adult.name} · break',
      startAt: parse(availability.breakStart!),
      endAt: parse(availability.breakEnd!),
      allDay: false,
      adultId: adult.id,
      sourceKind: 'break',
      sourceId: availability.id,
    );
  }
  if (availability.break2Start != null && availability.break2End != null) {
    yield CalendarEvent(
      id: 'break2:${adult.id}:${day.millisecondsSinceEpoch}',
      kind: CalendarEventKind.adultBreak,
      title: '${adult.name} · break',
      startAt: parse(availability.break2Start!),
      endAt: parse(availability.break2End!),
      allDay: false,
      adultId: adult.id,
      sourceKind: 'break',
      sourceId: availability.id,
    );
  }
  if (availability.lunchStart != null && availability.lunchEnd != null) {
    yield CalendarEvent(
      id: 'lunch:${adult.id}:${day.millisecondsSinceEpoch}',
      kind: CalendarEventKind.adultLunch,
      title: '${adult.name} · lunch',
      startAt: parse(availability.lunchStart!),
      endAt: parse(availability.lunchEnd!),
      allDay: false,
      adultId: adult.id,
      sourceKind: 'lunch',
      sourceId: availability.id,
    );
  }
}
