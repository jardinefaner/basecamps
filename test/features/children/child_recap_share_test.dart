import 'dart:convert';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/children/child_recap_share.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// "April 24 2026" is the date fixture every recap test renders
/// against so the weekday ("Fri") and the day-of-month ("24") are
/// stable across CI clock skew.
final _date = DateTime(2026, 4, 24);

Child _child({String firstName = 'Noah', String? groupId = 'g-butter'}) {
  return Child(
    id: 'c-noah',
    firstName: firstName,
    groupId: groupId,
    createdAt: _date,
    updatedAt: _date,
  );
}

ScheduleItem _item({
  required String id,
  required String title,
  String start = '09:00',
  String end = '10:00',
  bool fullDay = false,
  bool allGroups = true,
  List<String> groupIds = const [],
}) {
  return ScheduleItem(
    id: id,
    startTime: start,
    endTime: end,
    isFullDay: fullDay,
    title: title,
    isFromTemplate: true,
    groupIds: groupIds,
    allGroups: allGroups,
    date: _date,
  );
}

Observation _obs({
  required String id,
  required String note,
  String domain = 'ssd3',
  DateTime? createdAt,
}) {
  final stamp = createdAt ?? DateTime(2026, 4, 24, 10, 30);
  return Observation(
    id: id,
    targetKind: 'kids',
    domain: domain,
    sentiment: 'positive',
    note: note,
    createdAt: stamp,
    updatedAt: stamp,
  );
}

FormSubmission _incident({
  required String id,
  required String childId,
  required String description,
  DateTime? createdAt,
}) {
  final stamp = createdAt ?? DateTime(2026, 4, 24, 11, 15);
  return FormSubmission(
    id: id,
    formType: 'incident',
    status: 'completed',
    childId: childId,
    data: jsonEncode({'description': description}),
    createdAt: stamp,
    updatedAt: stamp,
  );
}

void main() {
  group('buildRecapText', () {
    test('full day with activities, observations, attendance', () {
      final recap = buildRecapText(
        child: _child(),
        date: _date,
        activities: [
          _item(
            id: 's1',
            title: 'Morning Circle',
            end: '09:45',
          ),
          _item(
            id: 's2',
            title: 'Art with Maya',
            start: '09:45',
            end: '10:30',
          ),
          _item(id: 's3', title: 'Snack', start: '10:30', end: '11:00'),
        ],
        observations: [
          _obs(id: 'o1', note: 'Helped Sam find his backpack'),
          _obs(
            id: 'o2',
            note: 'Took turns on the swing',
            domain: 'ssd5',
          ),
        ],
        domainsByObservationId: {
          'o1': [ObservationDomain.ssd3],
          'o2': [ObservationDomain.ssd5],
        },
        attendance: const AttendanceRecord(
          childId: 'c-noah',
          status: AttendanceStatus.present,
          clockTime: '08:32',
          pickupTime: '15:12',
          pickedUpBy: 'Mom',
        ),
        incidents: const [],
      );

      expect(recap.isEmpty, isFalse);
      expect(recap.text, contains("Hi, here's Noah's day on Fri, Apr 24"));
      expect(recap.text, contains('Morning Circle'));
      expect(recap.text, contains('9a\u20139:45a'));
      expect(recap.text, contains('Observations (2):'));
      expect(recap.text, contains('SSD3 (empathy)'));
      expect(recap.text, contains('SSD5 (follow rules)'));
      expect(
        recap.text,
        contains('checked in 8:32a, picked up 3:12p by Mom'),
      );
      expect(recap.text, contains('\u2014 Basecamp'));
    });

    test('skips the Observations section when none today', () {
      final recap = buildRecapText(
        child: _child(),
        date: _date,
        activities: [_item(id: 's1', title: 'Playground')],
        observations: const [],
        domainsByObservationId: const {},
        attendance: const AttendanceRecord(
          childId: 'c-noah',
          status: AttendanceStatus.present,
          clockTime: '08:32',
        ),
        incidents: const [],
      );

      expect(recap.text, isNot(contains('Observations')));
      expect(recap.isEmpty, isFalse);
    });

    test('no attendance row — section omitted', () {
      final recap = buildRecapText(
        child: _child(),
        date: _date,
        activities: [_item(id: 's1', title: 'Playground')],
        observations: const [],
        domainsByObservationId: const {},
        attendance: null,
        incidents: const [],
      );

      expect(recap.text, isNot(contains('Attendance')));
      expect(recap.text, contains('Playground'));
    });

    test('long observation notes are truncated with an ellipsis', () {
      final longNote = 'x' * 400;
      final recap = buildRecapText(
        child: _child(),
        date: _date,
        activities: const [],
        observations: [
          _obs(id: 'o1', note: longNote),
        ],
        domainsByObservationId: {
          'o1': [ObservationDomain.ssd3],
        },
        attendance: null,
        incidents: const [],
      );

      expect(recap.text, contains('\u2026'));
      // Note in the recap should be materially shorter than the input.
      final noteLine = recap.text
          .split('\n')
          .firstWhere((l) => l.startsWith('\u2022 SSD3'));
      expect(noteLine.length, lessThan(longNote.length));
    });

    test('incident rows render with description', () {
      final recap = buildRecapText(
        child: _child(),
        date: _date,
        activities: const [],
        observations: const [],
        domainsByObservationId: const {},
        attendance: null,
        incidents: [
          _incident(
            id: 'i1',
            childId: 'c-noah',
            description: 'Scraped knee on the playground',
          ),
          _incident(
            id: 'i2',
            childId: 'other-kid',
            description: 'For someone else',
          ),
        ],
      );

      expect(recap.text, contains('Incidents (1):'));
      expect(recap.text, contains('Scraped knee on the playground'));
      expect(recap.text, isNot(contains('For someone else')));
    });

    test('isEmpty true when nothing recorded for the day', () {
      final recap = buildRecapText(
        child: _child(),
        date: _date,
        activities: [
          // Staff-prep "no groups" item should be filtered out.
          _item(
            id: 'prep',
            title: 'Staff prep',
            allGroups: false,
          ),
        ],
        observations: const [],
        domainsByObservationId: const {},
        attendance: null,
        incidents: const [],
      );

      expect(recap.isEmpty, isTrue);
    });

    test('group-targeted activities only include matching group kids', () {
      final recap = buildRecapText(
        child: _child(),
        date: _date,
        activities: [
          _item(
            id: 's-mine',
            title: 'Butterflies Story Time',
            allGroups: false,
            groupIds: const ['g-butter'],
          ),
          _item(
            id: 's-theirs',
            title: 'Ladybugs Music',
            allGroups: false,
            groupIds: const ['g-lady'],
          ),
        ],
        observations: const [],
        domainsByObservationId: const {},
        attendance: null,
        incidents: const [],
      );

      expect(recap.text, contains('Butterflies Story Time'));
      expect(recap.text, isNot(contains('Ladybugs Music')));
    });
  });
}
