import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late LessonSequencesRepository repo;
  late ActivityLibraryRepository libRepo;

  setUp(() {
    db = createTestDatabase();
    container = createTestContainer();
    repo = LessonSequencesRepository(db, fakeRef(container));
    libRepo = ActivityLibraryRepository(db, fakeRef(container));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<String>> seedThree(String seqId) async {
    final a = await libRepo.addItem(title: 'A');
    final b = await libRepo.addItem(title: 'B');
    final c = await libRepo.addItem(title: 'C');
    final itemA =
        await repo.addItem(sequenceId: seqId, libraryItemId: a);
    final itemB =
        await repo.addItem(sequenceId: seqId, libraryItemId: b);
    final itemC =
        await repo.addItem(sequenceId: seqId, libraryItemId: c);
    return [itemA, itemB, itemC];
  }

  test('reorderItems writes new positions for the passed order', () async {
    final seqId = await repo.addSequence(name: 'Bug week');
    final items = await seedThree(seqId);

    // Move the third item to the front: [C, A, B].
    await repo.reorderItems(seqId, [items[2], items[0], items[1]]);

    final ordered = await repo.watchItemsFor(seqId).first;
    expect(ordered.map((i) => i.id).toList(),
        [items[2], items[0], items[1]]);
    expect(ordered.map((i) => i.position).toList(), [0, 1, 2]);
  });

  test('reorderItems is idempotent when order is unchanged', () async {
    final seqId = await repo.addSequence(name: 'No-op');
    final items = await seedThree(seqId);

    await repo.reorderItems(seqId, items);
    final ordered = await repo.watchItemsFor(seqId).first;
    expect(ordered.map((i) => i.position).toList(), [0, 1, 2]);
    expect(ordered.map((i) => i.id).toList(), items);
  });

  test('addItem assigns 0-based positions to consecutive inserts',
      () async {
    final seqId = await repo.addSequence(name: 'Sequence');
    final libA = await libRepo.addItem(title: 'A');
    final libB = await libRepo.addItem(title: 'B');
    await repo.addItem(sequenceId: seqId, libraryItemId: libA);
    await repo.addItem(sequenceId: seqId, libraryItemId: libB);
    final ordered = await repo.watchItemsFor(seqId).first;
    expect(ordered.map((i) => i.position).toList(), [0, 1]);
  });
}
