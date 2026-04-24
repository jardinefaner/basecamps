import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

/// Coverage for the two drag-move helpers on [ScheduleRepository]:
/// moveTemplateToDay flips the recurring weekday, and moveEntryToDate
/// shifts a one-off entry's date (preserving range length for multi-
/// day rows).
void main() {
  late AppDatabase db;
  late ScheduleRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = ScheduleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('moveTemplateToDay writes the new dayOfWeek', () async {
    final id = await repo.addTemplate(
      dayOfWeek: 1, // Monday
      startTime: '09:00',
      endTime: '10:00',
      title: 'Morning circle',
    );
    await repo.moveTemplateToDay(templateId: id, newDayOfWeek: 3);
    final row = await repo.getTemplate(id);
    expect(row, isNotNull);
    expect(row!.dayOfWeek, 3);
    // Other fields left alone.
    expect(row.startTime, '09:00');
    expect(row.title, 'Morning circle');
  });

  test('moveEntryToDate shifts a single-day entry', () async {
    final id = await repo.addOneOffEntry(
      date: DateTime(2026, 4, 20),
      startTime: '10:00',
      endTime: '10:45',
      title: 'Nature walk',
    );
    await repo.moveEntryToDate(
      entryId: id,
      newDate: DateTime(2026, 4, 22),
    );
    final row = await repo.getEntry(id);
    expect(row, isNotNull);
    expect(row!.date, DateTime(2026, 4, 22));
    expect(row.endDate, isNull);
  });

  test('moveEntryToDate preserves range length for multi-day entry',
      () async {
    // 3-day trip: Apr 20 → Apr 22.
    final id = await repo.addOneOffEntry(
      date: DateTime(2026, 4, 20),
      endDate: DateTime(2026, 4, 22),
      startTime: '09:00',
      endTime: '15:00',
      title: 'Zoo trip',
    );
    // Shift the start by +7 days — endDate should shift by the same
    // amount so the 3-day length is preserved.
    await repo.moveEntryToDate(
      entryId: id,
      newDate: DateTime(2026, 4, 27),
    );
    final row = await repo.getEntry(id);
    expect(row, isNotNull);
    expect(row!.date, DateTime(2026, 4, 27));
    expect(row.endDate, DateTime(2026, 4, 29));
  });
}
