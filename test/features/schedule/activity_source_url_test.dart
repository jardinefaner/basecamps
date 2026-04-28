import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

/// v40 coverage for per-activity source URLs. Smoke-tests the two
/// sides: addTemplate persists the column, and the merged-schedule
/// stream surfaces it on the resulting [ScheduleItem] so the detail
/// sheet can render the link row.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ScheduleRepository repo;

  setUp(() {
    db = createTestDatabase();
    container = createTestContainer(database: db);
    repo = ScheduleRepository(db, fakeRef(container));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('addTemplate persists sourceUrl', () async {
    final id = await repo.addTemplate(
      dayOfWeek: 1,
      startTime: '09:00',
      endTime: '10:00',
      title: 'Morning circle',
      sourceUrl: 'https://example.com/lesson-plan',
    );
    final template = await repo.getTemplate(id);
    expect(template, isNotNull);
    expect(template!.sourceUrl, 'https://example.com/lesson-plan');
  });

  test('ScheduleItem synthesis carries sourceUrl through', () async {
    // Find next Monday so `dayOfWeek: 1` matches the resolved day.
    final now = DateTime.now();
    final monday =
        DateTime(now.year, now.month, now.day).add(
      Duration(days: (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7),
    );
    await repo.addTemplate(
      dayOfWeek: 1,
      startTime: '09:00',
      endTime: '10:00',
      title: 'Morning circle',
      sourceUrl: 'https://example.com/recipe',
    );
    await repo.addTemplate(
      dayOfWeek: 1,
      startTime: '10:30',
      endTime: '11:00',
      title: 'Silent block',
    );

    final items = await repo.watchScheduleForDate(monday).first;
    expect(items, hasLength(2));
    final circle = items.firstWhere((i) => i.title == 'Morning circle');
    final silent = items.firstWhere((i) => i.title == 'Silent block');
    expect(circle.sourceUrl, 'https://example.com/recipe');
    expect(silent.sourceUrl, isNull);
  });
}
