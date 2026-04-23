import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/pods/pods_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pod is a derived view over groups + specialists + rooms + children.
/// These tests seed an in-memory DB with a realistic pod shape and
/// assert the join produces the right bundle. The join logic itself
/// is non-trivial (three indexes, two filters) and easy to regress.

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

ProviderContainer _container(AppDatabase db) {
  return ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
}

Future<void> _waitForPods(ProviderContainer c) async {
  // A derived Provider only reflects upstream stream values once those
  // streams have emitted — and Drift streams only emit while they
  // have an active listener. `listen(...)` wires one up for the span
  // of the test.
  final sub = c.listen<AsyncValue<List<Pod>>>(podsProvider, (_, _) {});
  addTearDown(sub.close);
  for (var i = 0; i < 20; i++) {
    if (sub.read().hasValue) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('podsProvider', () {
    test('joins group + leads + default room + child count', () async {
      final db = _db();
      addTearDown(db.close);

      // Two pods: Butterflies (anchored by Sarah), Ladybugs (anchored
      // by Mike + Jen). Plus a rotator (Alex) and an ambient (Pat) who
      // should NEVER appear as anchors regardless of whose group they
      // loosely point at.
      await db.into(db.groups).insert(
            GroupsCompanion.insert(id: 'g-b', name: 'Butterflies'),
          );
      await db.into(db.groups).insert(
            GroupsCompanion.insert(id: 'g-l', name: 'Ladybugs'),
          );

      await db.into(db.specialists).insert(
            SpecialistsCompanion.insert(
              id: 's-sarah',
              name: 'Sarah',
              adultRole: const Value('lead'),
              anchoredGroupId: const Value('g-b'),
            ),
          );
      await db.into(db.specialists).insert(
            SpecialistsCompanion.insert(
              id: 's-mike',
              name: 'Mike',
              adultRole: const Value('lead'),
              anchoredGroupId: const Value('g-l'),
            ),
          );
      await db.into(db.specialists).insert(
            SpecialistsCompanion.insert(
              id: 's-jen',
              name: 'Jen',
              adultRole: const Value('lead'),
              anchoredGroupId: const Value('g-l'),
            ),
          );
      await db.into(db.specialists).insert(
            SpecialistsCompanion.insert(
              id: 's-alex',
              name: 'Alex',
              // Specialist rotator with a leftover anchor — must NOT
              // show up in anchorLeads because role != lead.
              adultRole: const Value('specialist'),
              anchoredGroupId: const Value('g-b'),
            ),
          );
      await db.into(db.specialists).insert(
            SpecialistsCompanion.insert(
              id: 's-pat',
              name: 'Pat',
              adultRole: const Value('ambient'),
            ),
          );

      // Butterflies has a default room; Ladybugs doesn't yet.
      await db.into(db.rooms).insert(
            RoomsCompanion.insert(
              id: 'r-main',
              name: 'Main Room',
              defaultForGroupId: const Value('g-b'),
            ),
          );
      await db.into(db.rooms).insert(
            RoomsCompanion.insert(
              id: 'r-art',
              name: 'Art Room',
            ),
          );

      await db.into(db.children).insert(
            ChildrenCompanion.insert(
              id: 'k1',
              firstName: 'Noah',
              groupId: const Value('g-b'),
            ),
          );
      await db.into(db.children).insert(
            ChildrenCompanion.insert(
              id: 'k2',
              firstName: 'Mia',
              groupId: const Value('g-b'),
            ),
          );
      await db.into(db.children).insert(
            ChildrenCompanion.insert(
              id: 'k3',
              firstName: 'Leo',
              groupId: const Value('g-l'),
            ),
          );
      // Unassigned child — should be counted against no pod.
      await db.into(db.children).insert(
            ChildrenCompanion.insert(id: 'k4', firstName: 'Ava'),
          );

      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForPods(c);

      final pods = c.read(podsProvider).requireValue;
      expect(pods.map((p) => p.id).toSet(), {'g-b', 'g-l'});

      final butterflies = pods.firstWhere((p) => p.id == 'g-b');
      expect(butterflies.name, 'Butterflies');
      expect(butterflies.anchorLeads.map((s) => s.name).toList(), ['Sarah']);
      expect(butterflies.defaultRoom?.id, 'r-main');
      expect(butterflies.childCount, 2);

      final ladybugs = pods.firstWhere((p) => p.id == 'g-l');
      // Anchor leads sorted by name — Jen before Mike.
      expect(ladybugs.anchorLeads.map((s) => s.name).toList(),
          ['Jen', 'Mike']);
      expect(ladybugs.defaultRoom, isNull);
      expect(ladybugs.childCount, 1);
    });

    test('empty db → empty pod list', () async {
      final db = _db();
      addTearDown(db.close);
      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForPods(c);
      expect(c.read(podsProvider).requireValue, isEmpty);
    });

    test('specialist with lead role but no anchor is ignored', () async {
      final db = _db();
      addTearDown(db.close);
      await db.into(db.groups).insert(
            GroupsCompanion.insert(id: 'g-b', name: 'Butterflies'),
          );
      await db.into(db.specialists).insert(
            SpecialistsCompanion.insert(
              id: 's-1',
              name: 'Unassigned Lead',
              adultRole: const Value('lead'),
              // anchoredGroupId left null — a lead without a pod
              // assignment shouldn't appear on any pod.
            ),
          );

      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForPods(c);

      final pods = c.read(podsProvider).requireValue;
      expect(pods.single.anchorLeads, isEmpty);
    });
  });

  group('podProvider(id)', () {
    test('returns the matching pod', () async {
      final db = _db();
      addTearDown(db.close);
      await db.into(db.groups).insert(
            GroupsCompanion.insert(id: 'g-b', name: 'Butterflies'),
          );
      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForPods(c);
      expect(c.read(podProvider('g-b')).requireValue?.name, 'Butterflies');
    });

    test('returns null for an unknown id', () async {
      final db = _db();
      addTearDown(db.close);
      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForPods(c);
      expect(c.read(podProvider('nope')).requireValue, isNull);
    });
  });
}
