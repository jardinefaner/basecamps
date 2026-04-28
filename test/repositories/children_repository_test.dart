import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ChildrenRepository repo;

  setUp(() {
    db = createTestDatabase();
    container = createTestContainer(database: db);
    repo = ChildrenRepository(db, fakeRef(container));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('groups', () {
    test('addGroup + watchGroups', () async {
      final id = await repo.addGroup(name: 'Seedlings', colorHex: 'FF6B6B');
      final groups = await repo.watchGroups().first;
      expect(groups, hasLength(1));
      expect(groups.single.id, id);
      expect(groups.single.name, 'Seedlings');
      expect(groups.single.colorHex, 'FF6B6B');
    });

    test('updateGroup changes name, clearColor drops colorHex', () async {
      final id = await repo.addGroup(name: 'Seedlings', colorHex: 'FF6B6B');
      await repo.updateGroup(id: id, name: 'Dolphins');
      var g = await repo.getGroup(id);
      expect(g!.name, 'Dolphins');
      expect(g.colorHex, 'FF6B6B'); // not cleared

      await repo.updateGroup(id: id, clearColor: true);
      g = await repo.getGroup(id);
      expect(g!.colorHex, isNull);
    });

    test('deleteGroup removes the row', () async {
      final id = await repo.addGroup(name: 'Seedlings');
      await repo.deleteGroup(id);
      final groups = await repo.watchGroups().first;
      expect(groups, isEmpty);
    });
  });

  group('children', () {
    test('addChild + watchChildren', () async {
      final g = await repo.addGroup(name: 'Seedlings');
      final c = await repo.addChild(firstName: 'Maya', groupId: g);
      final children = await repo.watchChildren().first;
      expect(children, hasLength(1));
      expect(children.single.id, c);
      expect(children.single.firstName, 'Maya');
      expect(children.single.groupId, g);
    });

    test('watchChildrenInGroup filters by group', () async {
      final g1 = await repo.addGroup(name: 'Seedlings');
      final g2 = await repo.addGroup(name: 'Dolphins');
      await repo.addChild(firstName: 'Maya', groupId: g1);
      await repo.addChild(firstName: 'Noor', groupId: g2);
      await repo.addChild(firstName: 'Leo', groupId: g1);

      final seedlings = await repo.watchChildrenInGroup(g1).first;
      expect(seedlings.map((c) => c.firstName), containsAll(['Maya', 'Leo']));
      expect(seedlings.map((c) => c.firstName), isNot(contains('Noor')));
    });

    test('updateChild partial fields + clears', () async {
      final g = await repo.addGroup(name: 'Seedlings');
      final c = await repo.addChild(
        firstName: 'Maya',
        lastName: 'Johnson',
        groupId: g,
        notes: 'Peanut allergy',
      );

      await repo.updateChild(
        id: c,
        firstName: 'Mia',
        clearLastName: true,
      );
      var child = await repo.getChild(c);
      expect(child!.firstName, 'Mia');
      expect(child.lastName, isNull);
      expect(child.notes, 'Peanut allergy');

      await repo.updateChild(
        id: c,
        clearGroupId: true,
        clearNotes: true,
      );
      child = await repo.getChild(c);
      expect(child!.groupId, isNull);
      expect(child.notes, isNull);
    });

    test('updateChildGroup reassigns a child to a different group', () async {
      final g1 = await repo.addGroup(name: 'Seedlings');
      final g2 = await repo.addGroup(name: 'Dolphins');
      final c = await repo.addChild(firstName: 'Maya', groupId: g1);

      await repo.updateChildGroup(childId: c, groupId: g2);
      final child = await repo.getChild(c);
      expect(child!.groupId, g2);

      await repo.updateChildGroup(childId: c, groupId: null);
      final child2 = await repo.getChild(c);
      expect(child2!.groupId, isNull);
    });
  });

  group('FK cascade + setNull (regression: deleted kids appearing in '
      'tag picker)', () {
    test('deleteGroup nulls children.groupId (ON DELETE SET NULL)', () async {
      final g = await repo.addGroup(name: 'Seedlings');
      final c = await repo.addChild(firstName: 'Maya', groupId: g);
      await repo.deleteGroup(g);
      final child = await repo.getChild(c);
      expect(child, isNotNull);
      expect(child!.groupId, isNull,
          reason: 'ON DELETE SET NULL on children.group_id should fire');
    });

    test('deleteChild cascades into observation_children join', () async {
      final g = await repo.addGroup(name: 'Seedlings');
      final c = await repo.addChild(firstName: 'Maya', groupId: g);

      // Insert an observation + the join row directly via Drift.
      await db.into(db.observations).insert(
            ObservationsCompanion.insert(
              id: 'obs-1',
              targetKind: 'kids',
              domain: 'ssd1',
              sentiment: 'positive',
              note: 'Test',
            ),
          );
      await db.into(db.observationChildren).insert(
            ObservationChildrenCompanion.insert(
              observationId: 'obs-1',
              childId: c,
            ),
          );
      final before = await db.select(db.observationChildren).get();
      expect(before, hasLength(1));

      await repo.deleteChild(c);

      final after = await db.select(db.observationChildren).get();
      expect(after, isEmpty,
          reason: 'FK cascade should drop the join row when child is '
              'deleted — without this, the observation tag picker '
              'still showed the deleted child.');
    });

    test('deleteChild cascades into attendance rows', () async {
      final g = await repo.addGroup(name: 'Seedlings');
      final c = await repo.addChild(firstName: 'Maya', groupId: g);
      await db.into(db.attendance).insert(
            AttendanceCompanion.insert(
              childId: c,
              date: DateTime(2026),
              status: 'present',
            ),
          );
      expect(await db.select(db.attendance).get(), hasLength(1));
      await repo.deleteChild(c);
      expect(await db.select(db.attendance).get(), isEmpty);
    });
  });
}
