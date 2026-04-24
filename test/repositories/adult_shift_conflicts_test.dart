import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/adult_shift_conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure tests for the shift-window conflict detector — no DB needed,
/// we build model rows inline and feed them in.
ScheduleItem _item({
  required String id,
  String start = '10:00',
  String end = '11:00',
  bool isFullDay = false,
  String? adultId,
}) {
  return ScheduleItem(
    id: id,
    startTime: start,
    endTime: end,
    isFullDay: isFullDay,
    title: id,
    isFromTemplate: true,
    groupIds: const [],
    allGroups: true,
    adultId: adultId,
    date: DateTime(2026, 4, 20),
  );
}

AdultAvailabilityData _avail({
  required String adultId,
  required int dayOfWeek,
  String start = '09:00',
  String end = '15:00',
  String? breakStart,
  String? breakEnd,
  String? break2Start,
  String? break2End,
  String? lunchStart,
  String? lunchEnd,
}) {
  final now = DateTime(2026, 4, 20);
  return AdultAvailabilityData(
    id: 'av-$adultId-$dayOfWeek',
    adultId: adultId,
    dayOfWeek: dayOfWeek,
    startTime: start,
    endTime: end,
    breakStart: breakStart,
    breakEnd: breakEnd,
    break2Start: break2Start,
    break2End: break2End,
    lunchStart: lunchStart,
    lunchEnd: lunchEnd,
    createdAt: now,
    updatedAt: now,
  );
}

Adult _adult(String id, String name) => Adult(
      id: id,
      name: name,
      adultRole: 'specialist',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
    );

void main() {
  group('detectAdultShiftConflicts', () {
    test('flags activity that overlaps a break window', () {
      final item = _item(
        id: 'art',
        start: '10:30',
        adultId: 's1',
      );
      final result = detectAdultShiftConflicts(
        items: [item],
        availabilityByAdult: {
          's1': [
            _avail(
              adultId: 's1',
              dayOfWeek: 1,
              breakStart: '10:30',
              breakEnd: '10:45',
            ),
          ],
        },
        adultsById: {'s1': _adult('s1', 'Sarah')},
        isoWeekday: 1,
      );
      expect(result['art'], isNotNull);
      expect(result['art']!.length, 1);
      expect(result['art']!.first.kind, ShiftConflictKind.breakWindow);
      expect(result['art']!.first.reason, contains("Sarah's break"));
    });

    test('flags activity scheduled before shift start', () {
      final item = _item(
        id: 'early',
        start: '08:00',
        end: '09:00',
        adultId: 's1',
      );
      final result = detectAdultShiftConflicts(
        items: [item],
        availabilityByAdult: {
          's1': [_avail(adultId: 's1', dayOfWeek: 1)],
        },
        adultsById: {'s1': _adult('s1', 'Sarah')},
        isoWeekday: 1,
      );
      expect(result['early']!.first.kind, ShiftConflictKind.offShift);
      expect(result['early']!.first.reason, contains("Sarah's shift"));
    });

    test('flags activity on a day the adult has no availability', () {
      final item = _item(
        id: 'sat',
        adultId: 's1',
      );
      final result = detectAdultShiftConflicts(
        items: [item],
        // Adult works Mon–Fri; no Saturday row.
        availabilityByAdult: {
          's1': [_avail(adultId: 's1', dayOfWeek: 1)],
        },
        adultsById: {'s1': _adult('s1', 'Sarah')},
        isoWeekday: 6,
      );
      expect(result['sat']!.first.kind,
          ShiftConflictKind.noAvailabilityToday);
    });

    test('does NOT flag when activity sits outside the break window', () {
      final item = _item(
        id: 'story',
        start: '11:00',
        end: '12:00',
        adultId: 's1',
      );
      final result = detectAdultShiftConflicts(
        items: [item],
        availabilityByAdult: {
          's1': [
            _avail(
              adultId: 's1',
              dayOfWeek: 1,
              breakStart: '10:30',
              breakEnd: '10:45',
            ),
          ],
        },
        adultsById: {'s1': _adult('s1', 'Sarah')},
        isoWeekday: 1,
      );
      expect(result['story'], isNull);
    });

    test('flags lunch overlap with a restaurant-icon-ready reason', () {
      final item = _item(
        id: 'yoga',
        start: '12:15',
        end: '12:45',
        adultId: 's1',
      );
      final result = detectAdultShiftConflicts(
        items: [item],
        availabilityByAdult: {
          's1': [
            _avail(
              adultId: 's1',
              dayOfWeek: 1,
              lunchStart: '12:00',
              lunchEnd: '12:30',
            ),
          ],
        },
        adultsById: {'s1': _adult('s1', 'Sarah')},
        isoWeekday: 1,
      );
      expect(result['yoga']!.first.kind, ShiftConflictKind.lunchWindow);
    });

    test('skips items with no adult assigned', () {
      final item = _item(id: 'anon');
      final result = detectAdultShiftConflicts(
        items: [item],
        availabilityByAdult: const {},
        adultsById: const {},
        isoWeekday: 1,
      );
      expect(result, isEmpty);
    });

    test('skips full-day items', () {
      final item = _item(
        id: 'all-day',
        start: '00:00',
        end: '23:59',
        isFullDay: true,
        adultId: 's1',
      );
      final result = detectAdultShiftConflicts(
        items: [item],
        availabilityByAdult: const {},
        adultsById: {'s1': _adult('s1', 'Sarah')},
        isoWeekday: 1,
      );
      expect(result, isEmpty);
    });

    test('off-shift suppresses break overlap for the same item', () {
      // Activity 08:00–11:00 is before shift start (09:00) — even
      // though it overlaps the 10:30 break, we should only report
      // offShift (break-inside-offshift is redundant).
      final item = _item(
        id: 'double',
        start: '08:00',
        adultId: 's1',
      );
      final result = detectAdultShiftConflicts(
        items: [item],
        availabilityByAdult: {
          's1': [
            _avail(
              adultId: 's1',
              dayOfWeek: 1,
              breakStart: '10:30',
              breakEnd: '10:45',
            ),
          ],
        },
        adultsById: {'s1': _adult('s1', 'Sarah')},
        isoWeekday: 1,
      );
      expect(result['double']!.length, 1);
      expect(
        result['double']!.first.kind,
        ShiftConflictKind.offShift,
      );
    });
  });
}
