import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/trip_conflicts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure tests for the trip-conflict detector. Builds schedule items
/// and Trip rows inline — no DB required.

ScheduleItem _item({
  required String id,
  String start = '10:00',
  String end = '11:00',
  List<String> groupIds = const [],
  bool allGroups = false,
  String? title,
}) {
  return ScheduleItem(
    id: id,
    startTime: start,
    endTime: end,
    isFullDay: false,
    title: title ?? id,
    isFromTemplate: true,
    groupIds: groupIds,
    allGroups: allGroups,
    date: DateTime(2026, 4, 20),
  );
}

Trip _trip({
  required String id,
  required String name,
  String? depart,
  String? ret,
}) {
  final d = DateTime(2026, 4, 20);
  return Trip(
    id: id,
    name: name,
    date: d,
    departureTime: depart,
    returnTime: ret,
    createdAt: d,
    updatedAt: d,
  );
}

Group _group(String id, String name) => Group(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
    );

void main() {
  group('detectTripConflicts', () {
    test('flags activity whose group is on an overlapping trip', () {
      final item = _item(
        id: 'story',
        groupIds: const ['butter'],
      );
      final trip = _trip(
        id: 'zoo',
        name: 'Zoo',
        depart: '09:30',
        ret: '14:00',
      );
      final result = detectTripConflicts(
        scheduleItems: [item],
        todayTrips: [trip],
        groupsByTrip: const {
          'zoo': ['butter'],
        },
        groupsById: {'butter': _group('butter', 'Butterflies')},
      );
      expect(result.byActivityId['story'], isNotNull);
      expect(
        result.byActivityId['story']!.first.kind,
        TripConflictKind.tripOverlapsActivity,
      );
      expect(
        result.byActivityId['story']!.first.reason,
        contains('Butterflies'),
      );
      expect(result.byTripId['zoo'], isNotNull);
    });

    test('does NOT flag when trip and activity target different groups',
        () {
      final item = _item(
        id: 'story',
        groupIds: const ['sprouts'],
      );
      final trip = _trip(
        id: 'zoo',
        name: 'Zoo',
        depart: '09:30',
        ret: '14:00',
      );
      final result = detectTripConflicts(
        scheduleItems: [item],
        todayTrips: [trip],
        groupsByTrip: const {
          'zoo': ['butter'],
        },
        groupsById: {
          'butter': _group('butter', 'Butterflies'),
          'sprouts': _group('sprouts', 'Sprouts'),
        },
      );
      expect(result.byActivityId, isEmpty);
      expect(result.byTripId, isEmpty);
    });

    test('flags two same-day trips that share a group', () {
      final a = _trip(
        id: 'zoo',
        name: 'Zoo',
        depart: '09:00',
        ret: '12:00',
      );
      final b = _trip(
        id: 'farm',
        name: 'Farm',
        depart: '10:00',
        ret: '13:00',
      );
      final result = detectTripConflicts(
        scheduleItems: const [],
        todayTrips: [a, b],
        groupsByTrip: const {
          'zoo': ['butter'],
          'farm': ['butter', 'sprouts'],
        },
        groupsById: {
          'butter': _group('butter', 'Butterflies'),
          'sprouts': _group('sprouts', 'Sprouts'),
        },
      );
      expect(result.byTripId['zoo']?.length, 1);
      expect(result.byTripId['farm']?.length, 1);
      expect(
        result.byTripId['zoo']!.first.kind,
        TripConflictKind.tripOverlapsTrip,
      );
      expect(
        result.byTripId['zoo']!.first.reason,
        contains('Butterflies'),
      );
    });

    test('does NOT flag two trips when times do not overlap', () {
      final a = _trip(
        id: 'zoo',
        name: 'Zoo',
        depart: '09:00',
        ret: '10:00',
      );
      final b = _trip(
        id: 'farm',
        name: 'Farm',
        depart: '11:00',
        ret: '13:00',
      );
      final result = detectTripConflicts(
        scheduleItems: const [],
        todayTrips: [a, b],
        groupsByTrip: const {
          'zoo': ['butter'],
          'farm': ['butter'],
        },
        groupsById: {'butter': _group('butter', 'Butterflies')},
      );
      expect(result.byTripId, isEmpty);
    });

    test('program-wide trip (no groups) does NOT flag activities', () {
      final item = _item(
        id: 'story',
        groupIds: const ['butter'],
      );
      final trip = _trip(
        id: 'zoo',
        name: 'Zoo',
        depart: '09:30',
        ret: '14:00',
      );
      final result = detectTripConflicts(
        scheduleItems: [item],
        todayTrips: [trip],
        groupsByTrip: const {'zoo': <String>[]},
        groupsById: {'butter': _group('butter', 'Butterflies')},
      );
      expect(result.byActivityId, isEmpty);
    });

    test('all-groups activity is flagged by any trip', () {
      final item = _item(
        id: 'circle',
        allGroups: true,
      );
      final trip = _trip(
        id: 'zoo',
        name: 'Zoo',
        depart: '09:30',
        ret: '14:00',
      );
      final result = detectTripConflicts(
        scheduleItems: [item],
        todayTrips: [trip],
        groupsByTrip: const {
          'zoo': ['butter'],
        },
        groupsById: {'butter': _group('butter', 'Butterflies')},
      );
      expect(result.byActivityId['circle'], isNotNull);
    });

    test('trip without explicit times is treated as all-day', () {
      final item = _item(
        id: 'story',
        start: '15:00',
        end: '16:00',
        groupIds: const ['butter'],
      );
      final trip = _trip(id: 'zoo', name: 'Zoo');
      final result = detectTripConflicts(
        scheduleItems: [item],
        todayTrips: [trip],
        groupsByTrip: const {
          'zoo': ['butter'],
        },
        groupsById: {'butter': _group('butter', 'Butterflies')},
      );
      expect(result.byActivityId['story'], isNotNull);
    });
  });
}
