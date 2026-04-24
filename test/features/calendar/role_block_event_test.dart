import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/calendar/calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic AdultDayBlock row builder. The adapter only looks at id,
/// startTime, endTime, role, and groupId, but we fill everything for
/// DataClass equality + copy shape to stay honest.
AdultDayBlock _block({
  required String id,
  required String adultId,
  required String role,
  required String start,
  required String end,
  String? groupId,
}) =>
    AdultDayBlock(
      id: id,
      adultId: adultId,
      dayOfWeek: 4, // Thursday — matches the test "date" below.
      startTime: start,
      endTime: end,
      role: role,
      groupId: groupId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Adult _adult({String id = 's-sarah', String name = 'Sarah'}) => Adult(
      id: id,
      name: name,
      adultRole: 'lead',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final date = DateTime(2026, 4, 23); // Thursday

  group('calendarEventsFromAdultBlocks', () {
    test('a lead block emits a lead-kind event scoped to the group', () {
      final events = calendarEventsFromAdultBlocks(
        blocks: [
          _block(
            id: 'b1',
            adultId: 's-sarah',
            role: 'lead',
            start: '08:30',
            end: '11:00',
            groupId: 'g-butterflies',
          ),
        ],
        adult: _adult(),
        groupNameLookup: (id) =>
            id == 'g-butterflies' ? 'Butterflies' : '',
        date: date,
      ).toList();

      expect(events, hasLength(1));
      final ev = events.single;
      expect(ev.kind, CalendarEventKind.adultLeadBlock);
      expect(ev.title, 'Sarah → lead of Butterflies');
      expect(ev.startAt, DateTime(2026, 4, 23, 8, 30));
      expect(ev.endAt, DateTime(2026, 4, 23, 11));
      expect(ev.allDay, false);
      expect(ev.groupIds, ['g-butterflies']);
      expect(ev.adultId, 's-sarah');
      expect(ev.sourceKind, 'adult_day_block');
      expect(ev.sourceId, 'b1');
    });

    test('a specialist block emits a specialist-kind event with no '
        'groupIds', () {
      final events = calendarEventsFromAdultBlocks(
        blocks: [
          _block(
            id: 'b2',
            adultId: 's-sarah',
            role: 'specialist',
            start: '11:00',
            end: '12:00',
          ),
        ],
        adult: _adult(),
        // Lookup never called for specialist — returning garbage is
        // fine; the adapter shouldn't touch it.
        groupNameLookup: (_) => 'WRONG',
        date: date,
      ).toList();

      expect(events, hasLength(1));
      final ev = events.single;
      expect(ev.kind, CalendarEventKind.adultSpecialistBlock);
      expect(ev.title, 'Sarah → specialist');
      expect(ev.groupIds, isEmpty);
      expect(ev.adultId, 's-sarah');
    });

    test('a lead block with a missing groupId still emits — empty '
        'groupIds, neutral title', () {
      final events = calendarEventsFromAdultBlocks(
        blocks: [
          _block(
            id: 'b3',
            adultId: 's-sarah',
            role: 'lead',
            start: '09:00',
            end: '11:00',
            // null groupId: the data-quality case a sibling agent's
            // data-issue warning already surfaces. The adapter is
            // permissive — emit the row so the teacher at least sees
            // the time range.
          ),
        ],
        adult: _adult(),
        groupNameLookup: (_) => 'SHOULD_NOT_BE_USED',
        date: date,
      ).toList();

      expect(events, hasLength(1));
      final ev = events.single;
      expect(ev.kind, CalendarEventKind.adultLeadBlock);
      expect(ev.title, 'Sarah → lead');
      expect(ev.groupIds, isEmpty);
    });

    test('multiple blocks produce one event each, in input order', () {
      final events = calendarEventsFromAdultBlocks(
        blocks: [
          _block(
            id: 'b1',
            adultId: 's-sarah',
            role: 'lead',
            start: '08:30',
            end: '11:00',
            groupId: 'g-butterflies',
          ),
          _block(
            id: 'b2',
            adultId: 's-sarah',
            role: 'specialist',
            start: '11:00',
            end: '12:00',
          ),
          _block(
            id: 'b3',
            adultId: 's-sarah',
            role: 'lead',
            start: '12:00',
            end: '15:00',
            groupId: 'g-butterflies',
          ),
        ],
        adult: _adult(),
        groupNameLookup: (_) => 'Butterflies',
        date: date,
      ).toList();

      expect(events.map((e) => e.kind).toList(), [
        CalendarEventKind.adultLeadBlock,
        CalendarEventKind.adultSpecialistBlock,
        CalendarEventKind.adultLeadBlock,
      ]);
      expect(events.map((e) => e.sourceId).toList(), ['b1', 'b2', 'b3']);
    });
  });
}
