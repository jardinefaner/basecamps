import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/today/today_buckets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal ScheduleItem factory for bucketing tests — only fields the
/// bucket logic reads matter (start/end/isFullDay/title). Everything
/// else is set to stable defaults.
ScheduleItem _item({
  required String id,
  required String start,
  required String end,
  String title = 'Activity',
  bool fullDay = false,
}) =>
    ScheduleItem(
      id: id,
      startTime: start,
      endTime: end,
      isFullDay: fullDay,
      title: title,
      isFromTemplate: true,
      groupIds: const [],
      allGroups: true,
      date: DateTime(2026, 4, 23),
    );

int _at(int h, int m) => h * 60 + m;

void main() {
  group('bucketTodayItems', () {
    test('splits items into current / upcoming / past by now', () {
      final items = [
        _item(id: 'a', start: '08:00', end: '09:00', title: 'A'),
        _item(id: 'b', start: '10:00', end: '11:00', title: 'B'),
        _item(id: 'c', start: '14:00', end: '15:00', title: 'C'),
      ];
      final r = bucketTodayItems(items, _at(10, 30));
      expect(r.current.map((i) => i.id).toList(), ['b']);
      expect(r.past.map((i) => i.id).toList(), ['a']);
      expect(r.upcoming.map((i) => i.id).toList(), ['c']);
      expect(r.allDay, isEmpty);
    });

    test('boundary: exactly at start is current, exactly at end is past',
        () {
      final items = [
        _item(id: 'x', start: '10:00', end: '11:00'),
      ];
      // 10:00 → current
      expect(
        bucketTodayItems(items, _at(10, 0)).current.map((i) => i.id),
        ['x'],
      );
      // 11:00 → past (half-open interval)
      expect(
        bucketTodayItems(items, _at(11, 0)).past.map((i) => i.id),
        ['x'],
      );
      expect(
        bucketTodayItems(items, _at(11, 0)).current,
        isEmpty,
      );
    });

    test('concurrent activities all end up in current, earliest first',
        () {
      // Simulates a group running two things at 10:15 — one started at
      // 10:00, one started at 10:10. Before this bucket helper, the
      // second one would silently overwrite the first and disappear
      // from the Today view.
      final items = [
        _item(id: 'first', start: '10:00', end: '11:00', title: 'First'),
        _item(id: 'second', start: '10:10', end: '10:45', title: 'Second'),
      ];
      final r = bucketTodayItems(items, _at(10, 15));
      expect(r.current.map((i) => i.id).toList(), ['first', 'second']);
    });

    test('ties on start time fall back to title for stable ordering',
        () {
      final items = [
        _item(id: 'y', start: '10:00', end: '11:00', title: 'Yoga'),
        _item(id: 'a', start: '10:00', end: '11:00', title: 'Art'),
      ];
      final r = bucketTodayItems(items, _at(10, 30));
      // Same start; Art < Yoga alphabetically, so Art takes the hero.
      expect(r.current.map((i) => i.title).toList(), ['Art', 'Yoga']);
    });

    test('full-day items go to allDay, not current', () {
      final items = [
        _item(id: 'f', start: '00:00', end: '23:59', fullDay: true),
      ];
      final r = bucketTodayItems(items, _at(10, 30));
      expect(r.current, isEmpty);
      expect(r.allDay.map((i) => i.id).toList(), ['f']);
    });
  });
}
