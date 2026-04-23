import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/today/lateness.dart';
import 'package:flutter_test/flutter_test.dart';

Child _child({
  required String id,
  String name = 'Kid',
  String? expectedArrival,
  String? expectedPickup,
}) =>
    Child(
      id: id,
      firstName: name,
      expectedArrival: expectedArrival,
      expectedPickup: expectedPickup,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

AttendanceRecord _attendance(
  String childId,
  AttendanceStatus status, {
  String? pickupTime,
}) =>
    AttendanceRecord(
      childId: childId,
      status: status,
      pickupTime: pickupTime,
    );

ChildScheduleOverride _override(
  String childId, {
  String? arrival,
  String? note,
}) =>
    ChildScheduleOverride(
      id: 'o-$childId',
      childId: childId,
      date: DateTime(2026, 4, 23),
      expectedArrivalOverride: arrival,
      note: note,
      createdAt: DateTime(2026, 4, 23),
      updatedAt: DateTime(2026, 4, 23),
    );

DateTime _at(int h, int m) => DateTime(2026, 4, 23, h, m);

void main() {
  group('computeLatenessFlags', () {
    test('flags a kid past expected + grace who is not checked in', () {
      final kids = [_child(id: 'k1', expectedArrival: '08:30')];
      // 08:47 — 17 min past 08:30 → past the 15-min grace, should flag.
      final flags = computeLatenessFlags(
        now: _at(8, 47),
        children: kids,
        attendance: {},
        overrides: {},
      );
      expect(flags, hasLength(1));
      expect(flags.single.child.id, 'k1');
      expect(flags.single.expectedArrival, '08:30');
      expect(flags.single.minutesLate, 2); // 17 - 15 grace
    });

    test('does not flag within grace window', () {
      final kids = [_child(id: 'k1', expectedArrival: '08:30')];
      // 08:44 — 14 min past expected, inside grace.
      final flags = computeLatenessFlags(
        now: _at(8, 44),
        children: kids,
        attendance: {},
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('does not flag a present kid', () {
      final kids = [_child(id: 'k1', expectedArrival: '08:30')];
      final flags = computeLatenessFlags(
        now: _at(9, 0),
        children: kids,
        attendance: {
          'k1': _attendance('k1', AttendanceStatus.present),
        },
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('does not flag an absent kid', () {
      // Teacher already acted — we shouldn't nag.
      final kids = [_child(id: 'k1', expectedArrival: '08:30')];
      final flags = computeLatenessFlags(
        now: _at(9, 0),
        children: kids,
        attendance: {
          'k1': _attendance('k1', AttendanceStatus.absent),
        },
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('no expected arrival → never flagged', () {
      // Drop-in kid with no standing time; should never light up.
      final kids = [_child(id: 'k1')];
      final flags = computeLatenessFlags(
        now: _at(14, 0),
        children: kids,
        attendance: {},
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('daily override replaces standing arrival', () {
      // Standing 8:30 but override moved expectation to 9:30 today.
      // At 9:00 the child is NOT late relative to the override.
      final kids = [_child(id: 'k1', expectedArrival: '08:30')];
      final flags = computeLatenessFlags(
        now: _at(9, 0),
        children: kids,
        attendance: {},
        overrides: {
          'k1': _override('k1', arrival: '09:30', note: 'Mom texted'),
        },
      );
      expect(flags, isEmpty);
    });

    test('override carries note through to the flag', () {
      // Override moves expected to 09:00; at 09:30 they're 30 min past
      // expected, 15 min past grace — flag fires, note surfaces.
      final kids = [_child(id: 'k1', expectedArrival: '08:30')];
      final flags = computeLatenessFlags(
        now: _at(9, 30),
        children: kids,
        attendance: {},
        overrides: {
          'k1': _override('k1', arrival: '09:00', note: 'Mom texted'),
        },
      );
      expect(flags.single.note, 'Mom texted');
      expect(flags.single.expectedArrival, '09:00');
    });

    test('flags sorted worst-first', () {
      // k1 is 40 min late, k2 just crossed the line.
      final kids = [
        _child(id: 'k1', expectedArrival: '08:00'),
        _child(id: 'k2', expectedArrival: '08:40'),
      ];
      final flags = computeLatenessFlags(
        now: _at(8, 56),
        children: kids,
        attendance: {},
        overrides: {},
      );
      expect(flags.map((f) => f.child.id).toList(), ['k1', 'k2']);
    });
  });

  group('computeOverduePickupFlags', () {
    test('flags a present kid past pickup + grace with no pickup logged',
        () {
      final kids = [_child(id: 'k1', expectedPickup: '17:00')];
      // 17:16 — past 17:00 + 15 grace. No pickupTime recorded.
      final flags = computeOverduePickupFlags(
        now: _at(17, 17),
        children: kids,
        attendance: {
          'k1': _attendance('k1', AttendanceStatus.present),
        },
        overrides: {},
      );
      expect(flags, hasLength(1));
      expect(flags.single.minutesOverdue, 2); // 17 - 15 grace
      expect(flags.single.expectedPickup, '17:00');
    });

    test('does not flag within grace', () {
      final kids = [_child(id: 'k1', expectedPickup: '17:00')];
      final flags = computeOverduePickupFlags(
        now: _at(17, 14),
        children: kids,
        attendance: {
          'k1': _attendance('k1', AttendanceStatus.present),
        },
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('does not flag a kid whose pickup is already recorded', () {
      final kids = [_child(id: 'k1', expectedPickup: '17:00')];
      final flags = computeOverduePickupFlags(
        now: _at(18, 0),
        children: kids,
        attendance: {
          'k1': _attendance(
            'k1',
            AttendanceStatus.present,
            pickupTime: '17:05',
          ),
        },
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('does not flag a kid who never showed up (no attendance row)',
        () {
      final kids = [_child(id: 'k1', expectedPickup: '17:00')];
      // Absent-by-default → overdue pickup doesn't apply, they're
      // not on-site to be waiting.
      final flags = computeOverduePickupFlags(
        now: _at(18, 0),
        children: kids,
        attendance: {},
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('does not flag an explicitly absent kid', () {
      final kids = [_child(id: 'k1', expectedPickup: '17:00')];
      final flags = computeOverduePickupFlags(
        now: _at(18, 0),
        children: kids,
        attendance: {
          'k1': _attendance('k1', AttendanceStatus.absent),
        },
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('no expected pickup → never flagged', () {
      final kids = [_child(id: 'k1')];
      final flags = computeOverduePickupFlags(
        now: _at(20, 0),
        children: kids,
        attendance: {
          'k1': _attendance('k1', AttendanceStatus.present),
        },
        overrides: {},
      );
      expect(flags, isEmpty);
    });

    test('daily override replaces standing pickup', () {
      // Standing 5:00 but today override pushed to 6:30 — at 5:30
      // they're not overdue relative to the override.
      final kids = [_child(id: 'k1', expectedPickup: '17:00')];
      final flags = computeOverduePickupFlags(
        now: _at(17, 30),
        children: kids,
        attendance: {
          'k1': _attendance('k1', AttendanceStatus.present),
        },
        overrides: {
          'k1': ChildScheduleOverride(
            id: 'o1',
            childId: 'k1',
            date: DateTime(2026, 4, 23),
            expectedPickupOverride: '18:30',
            createdAt: DateTime(2026, 4, 23),
            updatedAt: DateTime(2026, 4, 23),
          ),
        },
      );
      expect(flags, isEmpty);
    });

    test('sorted most-overdue first', () {
      final kids = [
        _child(id: 'k1', expectedPickup: '16:00'),
        _child(id: 'k2', expectedPickup: '17:00'),
      ];
      // k1 overdue by 45 min (16:00 + 15 grace = 16:15, now 17:00 → 45 min)
      // k2 overdue by 0 min (just crossed 17:00 + 15 grace)
      final flags = computeOverduePickupFlags(
        now: _at(17, 15),
        children: kids,
        attendance: {
          'k1': _attendance('k1', AttendanceStatus.present),
          'k2': _attendance('k2', AttendanceStatus.present),
        },
        overrides: {},
      );
      expect(flags.map((f) => f.child.id).toList(), ['k1', 'k2']);
    });
  });
}
