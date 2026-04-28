import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ParentConcernRepository concerns;
  late ChildrenRepository kids;

  setUp(() {
    db = createTestDatabase();
    container = createTestContainer(database: db);
    concerns = ParentConcernRepository(db, fakeRef(container));
    kids = ChildrenRepository(db, fakeRef(container));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('create / update', () {
    test('create persists every field from the input', () async {
      final input = ParentConcernInput(
        childNames: 'Maya, Leo',
        parentName: 'Amy Chen',
        concernDate: DateTime(2026, 4, 20),
        staffReceiving: 'Ms. Park',
        methodInPerson: true,
        concernDescription: 'Lunch ran long',
        immediateResponse: 'Sent a note home',
      );
      final id = await concerns.create(input);
      final row = await concerns.getOne(id);
      expect(row!.childNames, 'Maya, Leo');
      expect(row.parentName, 'Amy Chen');
      expect(row.staffReceiving, 'Ms. Park');
      expect(row.methodInPerson, isTrue);
      expect(row.concernDescription, 'Lunch ran long');
      expect(row.immediateResponse, 'Sent a note home');
    });

    test('update replaces every field, not a partial patch', () async {
      final id = await concerns.create(
        ParentConcernInput(
          childNames: 'Maya',
          parentName: 'Amy',
          concernDescription: 'First',
        ),
      );
      await concerns.update(
        id,
        ParentConcernInput(
          childNames: 'Maya',
          parentName: 'Amy',
          concernDescription: 'Second',
          // nothing else set; defaults replace the old values
        ),
      );
      final row = await concerns.getOne(id);
      expect(row!.concernDescription, 'Second');
      expect(row.immediateResponse, '');
    });
  });

  group('structured concern↔child links', () {
    test('create writes child join rows', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final maya = await kids.addChild(firstName: 'Maya', groupId: g);
      final leo = await kids.addChild(firstName: 'Leo', groupId: g);
      final id = await concerns.create(
        ParentConcernInput(
          childNames: 'Maya, Leo',
          parentName: 'Amy',
          childIds: [maya, leo],
        ),
      );
      final linked = await concerns.childIdsForConcern(id);
      expect(linked, containsAll([maya, leo]));
    });

    test('update replaces the links wholesale', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final maya = await kids.addChild(firstName: 'Maya', groupId: g);
      final leo = await kids.addChild(firstName: 'Leo', groupId: g);
      final jordan = await kids.addChild(firstName: 'Jordan', groupId: g);

      final id = await concerns.create(
        ParentConcernInput(
          childNames: 'Maya, Leo',
          parentName: 'Amy',
          childIds: [maya, leo],
        ),
      );
      await concerns.update(
        id,
        ParentConcernInput(
          childNames: 'Jordan',
          parentName: 'Amy',
          childIds: [jordan],
        ),
      );
      final linked = await concerns.childIdsForConcern(id);
      expect(linked, [jordan]);
    });

    test('watchConcernKidLinks emits the full map', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final maya = await kids.addChild(firstName: 'Maya', groupId: g);
      final leo = await kids.addChild(firstName: 'Leo', groupId: g);

      final a = await concerns.create(
        ParentConcernInput(
          childNames: 'Maya',
          parentName: 'Amy',
          childIds: [maya],
        ),
      );
      final b = await concerns.create(
        ParentConcernInput(
          childNames: 'Leo',
          parentName: 'Jim',
          childIds: [leo],
        ),
      );
      final map = await concerns.watchConcernChildLinks().first;
      expect(map[a], {maya});
      expect(map[b], {leo});
    });
  });

  group('watchForDay (Today flag)', () {
    test('picks up notes with concernDate matching', () async {
      final today = DateTime(2026, 4, 20);
      await concerns.create(
        ParentConcernInput(
          childNames: 'Maya',
          parentName: 'Amy',
          concernDate: today,
        ),
      );
      await concerns.create(
        ParentConcernInput(
          childNames: 'Leo',
          parentName: 'Jim',
          concernDate: DateTime(2026, 4, 19),
        ),
      );
      final todays = await concerns.watchForDay(today).first;
      expect(todays, hasLength(1));
      expect(todays.single.childNames, 'Maya');
    });
  });

  group('FK cascade: deleting a child cleans up concern links', () {
    test('deleteChild drops parent_concern_children row', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final maya = await kids.addChild(firstName: 'Maya', groupId: g);
      final id = await concerns.create(
        ParentConcernInput(
          childNames: 'Maya',
          parentName: 'Amy',
          childIds: [maya],
        ),
      );
      expect(await concerns.childIdsForConcern(id), [maya]);
      await kids.deleteChild(maya);
      expect(await concerns.childIdsForConcern(id), isEmpty);
    });
  });
}
