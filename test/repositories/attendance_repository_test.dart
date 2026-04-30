import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late AttendanceRepository att;
  late ChildrenRepository kids;

  setUp(() {
    db = createTestDatabase();
    container = createTestContainer(database: db);
    att = AttendanceRepository(db, fakeRef(container));
    kids = ChildrenRepository(db, fakeRef(container));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('setStatus / clearStatus / watchForDay', () {
    test('setStatus writes a row with the right status name', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final c = await kids.addChild(firstName: 'Maya', groupId: g);
      final date = DateTime(2026, 4, 20);
      await att.setStatus(
        childId: c,
        date: date,
        status: AttendanceStatus.present,
      );
      final map = await att.watchForDay(date).first;
      expect(map, hasLength(1));
      expect(map[c]!.status, AttendanceStatus.present);
    });

    test('setStatus upserts — second call replaces, no duplicate row',
        () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final c = await kids.addChild(firstName: 'Maya', groupId: g);
      final date = DateTime(2026, 4, 20);
      await att.setStatus(
        childId: c,
        date: date,
        status: AttendanceStatus.present,
      );
      await att.setStatus(
        childId: c,
        date: date,
        status: AttendanceStatus.absent,
      );
      final rows = await db.select(db.attendance).get();
      expect(rows, hasLength(1));
      expect(rows.single.status, 'absent');
    });

    test('clearStatus removes the row (back to pending)', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final c = await kids.addChild(firstName: 'Maya', groupId: g);
      final date = DateTime(2026, 4, 20);
      await att.setStatus(
        childId: c,
        date: date,
        status: AttendanceStatus.present,
      );
      await att.clearStatus(childId: c, date: date);
      final map = await att.watchForDay(date).first;
      expect(map, isEmpty);
    });

    test('watchForDay scopes by date', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final c = await kids.addChild(firstName: 'Maya', groupId: g);
      final day1 = DateTime(2026, 4, 20);
      final day2 = DateTime(2026, 4, 21);
      await att.setStatus(
        childId: c,
        date: day1,
        status: AttendanceStatus.present,
      );
      await att.setStatus(
        childId: c,
        date: day2,
        status: AttendanceStatus.absent,
      );
      expect((await att.watchForDay(day1).first)[c]!.status,
          AttendanceStatus.present);
      expect((await att.watchForDay(day2).first)[c]!.status,
          AttendanceStatus.absent);
    });
  });

  group('markAllPresent', () {
    test('marks every child in the roster as present in one txn', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final roster = <String>[];
      for (final name in ['Maya', 'Jordan', 'Leo']) {
        roster.add(await kids.addChild(firstName: name, groupId: g));
      }
      final date = DateTime(2026, 4, 20);
      await att.markAllPresent(childIds: roster, date: date);
      final map = await att.watchForDay(date).first;
      for (final id in roster) {
        expect(map[id]!.status, AttendanceStatus.present);
      }
    });
  });

  group('AttendanceStatus.fromName', () {
    test('round-trips every enum value', () {
      for (final s in AttendanceStatus.values) {
        expect(AttendanceStatus.fromName(s.name), s);
      }
    });

    test('returns null on unknown', () {
      expect(AttendanceStatus.fromName('bogus'), isNull);
      expect(AttendanceStatus.fromName(null), isNull);
    });
  });
}
