import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ThemesRepository repo;

  setUp(() {
    db = createTestDatabase();
    container = createTestContainer(database: db);
    repo = ThemesRepository(db, fakeRef(container));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('watchActive includes themes that cover the date (inclusive bounds)',
      () async {
    await repo.addTheme(
      name: 'Bug week',
      startDate: DateTime(2026, 4, 20),
      endDate: DateTime(2026, 4, 24),
    );
    // Start date — inclusive.
    expect(
      (await repo.watchActive(DateTime(2026, 4, 20)).first)
          .map((t) => t.name),
      ['Bug week'],
    );
    // End date — inclusive.
    expect(
      (await repo.watchActive(DateTime(2026, 4, 24)).first)
          .map((t) => t.name),
      ['Bug week'],
    );
    // Midpoint.
    expect(
      (await repo.watchActive(DateTime(2026, 4, 22)).first)
          .map((t) => t.name),
      ['Bug week'],
    );
  });

  test('watchActive excludes themes outside the date range', () async {
    await repo.addTheme(
      name: 'Bug week',
      startDate: DateTime(2026, 4, 20),
      endDate: DateTime(2026, 4, 24),
    );
    // Day before start.
    expect(
      (await repo.watchActive(DateTime(2026, 4, 19)).first).isEmpty,
      isTrue,
    );
    // Day after end.
    expect(
      (await repo.watchActive(DateTime(2026, 4, 25)).first).isEmpty,
      isTrue,
    );
  });
}
