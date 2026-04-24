import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/calendar/calendar_event.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleItem _item({
  required String id,
  required String title,
  required String start,
  required String end,
  bool fullDay = false,
  List<String> groupIds = const [],
  bool allGroups = false,
  String? adultId,
  String? templateId,
  String? entryId,
  DateTime? date,
}) =>
    ScheduleItem(
      id: id,
      startTime: start,
      endTime: end,
      isFullDay: fullDay,
      title: title,
      isFromTemplate: templateId != null,
      groupIds: groupIds,
      allGroups: allGroups,
      adultId: adultId,
      templateId: templateId,
      entryId: entryId,
      date: date ?? DateTime(2026, 4, 23),
    );

Trip _trip({
  required String id,
  required String name,
  String? departure,
  String? returnT,
  DateTime? date,
  DateTime? endDate,
  String? location,
}) =>
    Trip(
      id: id,
      name: name,
      date: date ?? DateTime(2026, 4, 23),
      endDate: endDate,
      departureTime: departure,
      returnTime: returnT,
      location: location,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('calendarEventFromScheduleItem', () {
    test('maps a timed activity to a CalendarEvent with correct times',
        () {
      final item = _item(
        id: 'a',
        title: 'Art',
        start: '09:00',
        end: '10:00',
        templateId: 'tpl-1',
        groupIds: ['g-b'],
        adultId: 's-sarah',
      );
      final ev = calendarEventFromScheduleItem(item);
      expect(ev.kind, CalendarEventKind.activity);
      expect(ev.title, 'Art');
      expect(ev.startAt, DateTime(2026, 4, 23, 9));
      expect(ev.endAt, DateTime(2026, 4, 23, 10));
      expect(ev.allDay, false);
      expect(ev.groupIds, ['g-b']);
      expect(ev.adultId, 's-sarah');
      expect(ev.sourceKind, 'template');
      expect(ev.sourceId, 'tpl-1');
      expect(ev.durationMinutes, 60);
    });

    test('full-day item spans midnight-to-midnight', () {
      final item = _item(
        id: 'f',
        title: 'Field trip',
        start: '00:00',
        end: '23:59',
        fullDay: true,
        entryId: 'ent-1',
      );
      final ev = calendarEventFromScheduleItem(item);
      expect(ev.allDay, true);
      expect(ev.startAt, DateTime(2026, 4, 23));
      expect(ev.endAt, DateTime(2026, 4, 24));
      expect(ev.sourceKind, 'entry');
      expect(ev.sourceId, 'ent-1');
      expect(ev.durationMinutes, 0); // all-day events don't report
    });

    test('activityLabel-style metadata flows into subtitle + fields',
        () {
      final item = _item(
        id: 'a',
        title: 'Outdoor Play',
        start: '10:00',
        end: '11:00',
        templateId: 'tpl-2',
      );
      final ev = calendarEventFromScheduleItem(item);
      expect(ev.roomId, isNull);
      expect(ev.location, isNull);
    });
  });

  group('calendarEventFromTrip', () {
    test('a trip with departure + return times is treated as timed', () {
      final trip = _trip(
        id: 't1',
        name: 'Aquarium',
        departure: '09:30',
        returnT: '14:00',
        location: 'Monterey Bay',
      );
      final ev = calendarEventFromTrip(trip);
      expect(ev.kind, CalendarEventKind.trip);
      expect(ev.title, 'Aquarium');
      expect(ev.startAt, DateTime(2026, 4, 23, 9, 30));
      expect(ev.endAt, DateTime(2026, 4, 23, 14));
      expect(ev.allDay, false);
      expect(ev.location, 'Monterey Bay');
      expect(ev.sourceKind, 'trip');
      expect(ev.sourceId, 't1');
    });

    test('a trip with no times is all-day spanning the date range', () {
      final trip = _trip(
        id: 't2',
        name: 'Camping',
        date: DateTime(2026, 4, 23),
        endDate: DateTime(2026, 4, 25),
      );
      final ev = calendarEventFromTrip(trip);
      expect(ev.allDay, true);
      expect(ev.startAt, DateTime(2026, 4, 23));
      // Inclusive end → endAt is the START of the day AFTER the
      // last covered day, so a 3-day trip (23/24/25) ends at 26.
      expect(ev.endAt, DateTime(2026, 4, 26));
    });
  });
}
