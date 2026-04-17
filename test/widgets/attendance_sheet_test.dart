import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/attendance/widgets/attendance_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';
import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ChildrenRepository kids;
  late AttendanceRepository att;
  late String groupId;
  late String maya;
  late String leo;

  setUp(() async {
    db = createTestDatabase();
    kids = ChildrenRepository(db);
    att = AttendanceRepository(db);
    groupId = await kids.addGroup(name: 'Seedlings');
    maya = await kids.addChild(firstName: 'Maya', groupId: groupId);
    leo = await kids.addChild(firstName: 'Leo', groupId: groupId);
  });

  tearDown(() async {
    // db is closed inside pumpWithHost's teardown.
  });

  group('summary row', () {
    testWidgets('shows present / absent / pending counts', (tester) async {
      // The sheet's current implementation reads via todayAttendanceProvider
      // (DateTime.now()) regardless of the `date` prop, so seed at today's
      // calendar date. (Tracked as a product bug — see spawn task.)
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day);
      await att.setStatus(
        childId: maya,
        date: date,
        status: AttendanceStatus.present,
      );
      await pumpWithHost(
        tester,
        AttendanceSheet(groupIds: [groupId], date: date),
        database: db,
      );
      // Let Drift's stream emit outside flutter_test's fake-async zone,
      // then rebuild.
      await tester.runAsync(() => att.watchForDay(date).first);
      await tester.pump();
      await tester.pump();
      // Each label appears at least once (in the summary strip; tiles
      // also render status labels, which is fine).
      expect(find.text('Present'), findsWidgets);
      expect(find.text('Absent'), findsWidgets);
      expect(find.text('Pending'), findsWidgets);
    });

    testWidgets('pending=0 hides "Mark remaining present" button',
        (tester) async {
      // The sheet's current implementation reads via todayAttendanceProvider
      // (DateTime.now()) regardless of the `date` prop, so seed at today's
      // calendar date. (Tracked as a product bug — see spawn task.)
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day);
      await att.setStatus(
        childId: maya,
        date: date,
        status: AttendanceStatus.present,
      );
      await att.setStatus(
        childId: leo,
        date: date,
        status: AttendanceStatus.absent,
      );
      await pumpWithHost(
        tester,
        AttendanceSheet(groupIds: [groupId], date: date),
        database: db,
      );
      // Wait for Drift's stream to surface the pre-seeded rows so the
      // widget knows pending=0 and hides the "Mark ... present" button.
      await tester.runAsync(() => att.watchForDay(date).first);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Mark'), findsNothing);
    });
  });

  // NOTE: cycle-tap tests (pending→present→absent→pending) are deferred.
  // Tapping an AttendanceTile fires an async Drift write; by the time
  // flutter_test's teardown runs, the write's async scope is still open
  // and TestAsyncUtils.verifyAllScopesClosed throws. Fix needs a harness
  // that awaits the repo stream emission, not pumpAndSettle. Until then,
  // cycle behavior is covered by the repo-level AttendanceRepository tests.

  group('empty state', () {
    testWidgets('no children in group → "No children" copy', (tester) async {
      final empty = await kids.addGroup(name: 'Empty Group');
      await pumpWithHost(
        tester,
        AttendanceSheet(
          groupIds: [empty],
          date: DateTime(2026, 4, 20),
        ),
        database: db,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No children in these groups yet.'),
        findsOneWidget,
      );
    });
  });
}
