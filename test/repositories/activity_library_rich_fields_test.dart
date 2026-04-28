import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

/// Locks in the invariant that [ActivityLibraryRepository.updateItem]
/// only touches fields the caller explicitly passes. Regression guard
/// for the "edit sheet wipes AI-generated card" bug.
void main() {
  test('updateItem leaves absent fields untouched', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final container = createTestContainer();
    addTearDown(container.dispose);
    final repo = ActivityLibraryRepository(db, fakeRef(container));

    // Seed a richly-populated card — this is what the AI wizard
    // writes on save.
    final id = await repo.addItem(
      title: 'Tide pools',
      audienceMinAge: 5,
      audienceMaxAge: 7,
      hook: 'Tiny oceans, huge surprises.',
      summary: 'Tide pools fill with creatures when the sea pulls back.',
      keyPoints: 'Anemones\nStarfish\nHermit crabs',
      learningGoals: 'Name three tide pool animals',
      engagementTimeMin: 20,
      sourceUrl: 'https://example.com/tide-pools',
      sourceAttribution: 'via example.com',
    );

    // Simulate the edit sheet saving just a title change. Before the
    // fix, this blew away every rich field because the repo wrote
    // Value(null) for each arg that defaulted to null.
    await repo.updateItem(id: id, title: 'Tide pools (updated)');

    final row = await repo.getItem(id);
    expect(row, isNotNull);
    expect(row!.title, 'Tide pools (updated)');
    // Every other field should survive the partial update.
    expect(row.audienceMinAge, 5);
    expect(row.audienceMaxAge, 7);
    expect(row.hook, 'Tiny oceans, huge surprises.');
    expect(row.summary, contains('creatures'));
    expect(row.keyPoints, contains('Starfish'));
    expect(row.learningGoals, 'Name three tide pool animals');
    expect(row.engagementTimeMin, 20);
    expect(row.sourceUrl, 'https://example.com/tide-pools');
    expect(row.sourceAttribution, 'via example.com');
  });

  test('updateItem DOES null a field when explicitly set to Value(null)', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final container = createTestContainer();
    addTearDown(container.dispose);
    final repo = ActivityLibraryRepository(db, fakeRef(container));

    final id = await repo.addItem(
      title: 'Art',
      hook: 'Paint with purpose.',
      summary: 'Art is about expression.',
    );

    // Caller wants to clear the hook — pass Value(null) explicitly.
    await repo.updateItem(id: id, hook: const Value(null));

    final row = await repo.getItem(id);
    expect(row!.hook, isNull, reason: 'Value(null) should clear the hook');
    expect(row.summary, 'Art is about expression.',
        reason: 'summary was absent → should remain');
  });
}
