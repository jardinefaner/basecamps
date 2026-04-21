import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

/// Repo-level canaries for the user's bug report: "can't add any activity
/// recurring more than one day and date ranged." If these pass, the bug
/// lives in the wizard UI, not in the data layer.
void main() {
  late AppDatabase db;
  late ScheduleRepository schedule;

  setUp(() {
    db = createTestDatabase();
    schedule = ScheduleRepository(db);
  });

  tearDown(() async => db.close());

  group('multi-day recurring activity', () {
    test('addTemplate in a loop creates one row per picked day', () async {
      final seriesId = newId();
      // Simulates the wizard picking Mon+Tue+Wed+Thu+Fri and tapping
      // "Create on 5 days".
      for (final day in [1, 2, 3, 4, 5]) {
        await schedule.addTemplate(
          dayOfWeek: day,
          startTime: '09:00',
          endTime: '10:00',
          title: 'Morning circle',
          seriesId: seriesId,
        );
      }
      final rows = await db.select(db.scheduleTemplates).get();
      expect(rows, hasLength(5));
      expect(rows.map((r) => r.dayOfWeek).toList()..sort(),
          [1, 2, 3, 4, 5]);
      expect(rows.every((r) => r.seriesId == seriesId), isTrue);
    });

    test('multi-day with a startDate+endDate range persists all bounds',
        () async {
      final seriesId = newId();
      final start = DateTime(2026, 5, 4); // Mon
      final end = DateTime(2026, 5, 29); // Fri — ~4 weeks
      for (final day in [1, 3, 5]) {
        await schedule.addTemplate(
          dayOfWeek: day,
          startTime: '09:00',
          endTime: '10:00',
          title: 'Swim',
          seriesId: seriesId,
          startDate: start,
          endDate: end,
        );
      }
      final rows = await db.select(db.scheduleTemplates).get();
      expect(rows, hasLength(3));
      for (final r in rows) {
        expect(r.startDate, DateTime(2026, 5, 4));
        expect(r.endDate, DateTime(2026, 5, 29));
      }
    });

    test('watchScheduleForWeek inside the range surfaces all picked days',
        () async {
      // Seed Mon/Wed/Fri, date-ranged to span the week of May 4–8 2026.
      final seriesId = newId();
      final start = DateTime(2026, 5, 4);
      final end = DateTime(2026, 5, 8);
      for (final day in [1, 3, 5]) {
        await schedule.addTemplate(
          dayOfWeek: day,
          startTime: '09:00',
          endTime: '10:00',
          title: 'Swim',
          seriesId: seriesId,
          startDate: start,
          endDate: end,
        );
      }
      final byDay = await schedule.watchScheduleForWeek(start).first;
      expect(byDay[1], hasLength(1), reason: 'Monday should have Swim');
      expect(byDay[3], hasLength(1), reason: 'Wednesday should have Swim');
      expect(byDay[5], hasLength(1), reason: 'Friday should have Swim');
      expect(byDay[2] ?? const [], isEmpty);
      expect(byDay[4] ?? const [], isEmpty);
    });

    test('watchScheduleForWeek OUTSIDE the range shows nothing', () async {
      // Seed May 4–8, then view week of May 11–15 → should be empty.
      final seriesId = newId();
      for (final day in [1, 3, 5]) {
        await schedule.addTemplate(
          dayOfWeek: day,
          startTime: '09:00',
          endTime: '10:00',
          title: 'Swim',
          seriesId: seriesId,
          startDate: DateTime(2026, 5, 4),
          endDate: DateTime(2026, 5, 8),
        );
      }
      final nextWeek = await schedule
          .watchScheduleForWeek(DateTime(2026, 5, 11))
          .first;
      expect(
        nextWeek.values.expand((l) => l).toList(),
        isEmpty,
        reason:
            'Templates with endDate before the viewed week must not leak in',
      );
    });
  });
}
