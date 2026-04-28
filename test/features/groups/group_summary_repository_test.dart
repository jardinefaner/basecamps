import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// GroupSummary is a derived view over groups + adults + rooms +
/// children. These tests seed an in-memory DB with a realistic group
/// shape and assert the join produces the right bundle. The join
/// logic itself is non-trivial (three indexes, two filters) and easy
/// to regress.

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

/// `groupsProvider` (and the rest of the program-scoped providers)
/// now `ref.watch(activeProgramIdProvider)` so they rebuild on
/// program switch. The default notifier hydrates from
/// SharedPreferences, which crashes a non-binding test. Pin it to
/// null with a stub so the in-memory DB just sees the legacy
/// program_id IS NULL arm.
class _NullActiveProgramNotifier extends ActiveProgramNotifier {
  @override
  String? build() => null;
}

ProviderContainer _container(AppDatabase db) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      activeProgramIdProvider.overrideWith(_NullActiveProgramNotifier.new),
    ],
  );
}

Future<void> _waitForSummaries(ProviderContainer c) async {
  // A derived Provider only reflects upstream stream values once those
  // streams have emitted — and Drift streams only emit while they
  // have an active listener. `listen(...)` wires one up for the span
  // of the test.
  final sub = c.listen<AsyncValue<List<GroupSummary>>>(
    groupSummariesProvider,
    (_, _) {},
  );
  addTearDown(sub.close);
  for (var i = 0; i < 20; i++) {
    if (sub.read().hasValue) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('groupSummariesProvider', () {
    test('joins group + leads + default room + child count', () async {
      final db = _db();
      addTearDown(db.close);

      // Two groups: Butterflies (anchored by Sarah), Ladybugs (anchored
      // by Mike + Jen). Plus a rotator (Alex) and an ambient (Pat) who
      // should NEVER appear as anchors regardless of whose group they
      // loosely point at.
      await db.into(db.groups).insert(
            GroupsCompanion.insert(id: 'g-b', name: 'Butterflies'),
          );
      await db.into(db.groups).insert(
            GroupsCompanion.insert(id: 'g-l', name: 'Ladybugs'),
          );

      await db.into(db.adults).insert(
            AdultsCompanion.insert(
              id: 's-sarah',
              name: 'Sarah',
              adultRole: const Value('lead'),
              anchoredGroupId: const Value('g-b'),
            ),
          );
      await db.into(db.adults).insert(
            AdultsCompanion.insert(
              id: 's-mike',
              name: 'Mike',
              adultRole: const Value('lead'),
              anchoredGroupId: const Value('g-l'),
            ),
          );
      await db.into(db.adults).insert(
            AdultsCompanion.insert(
              id: 's-jen',
              name: 'Jen',
              adultRole: const Value('lead'),
              anchoredGroupId: const Value('g-l'),
            ),
          );
      await db.into(db.adults).insert(
            AdultsCompanion.insert(
              id: 's-alex',
              name: 'Alex',
              // Adult rotator with a leftover anchor — must NOT
              // show up in anchorLeads because role != lead.
              adultRole: const Value('adult'),
              anchoredGroupId: const Value('g-b'),
            ),
          );
      await db.into(db.adults).insert(
            AdultsCompanion.insert(
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
      // Unassigned child — should be counted against no group.
      await db.into(db.children).insert(
            ChildrenCompanion.insert(id: 'k4', firstName: 'Ava'),
          );

      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForSummaries(c);

      final summaries = c.read(groupSummariesProvider).requireValue;
      expect(summaries.map((s) => s.id).toSet(), {'g-b', 'g-l'});

      final butterflies = summaries.firstWhere((s) => s.id == 'g-b');
      expect(butterflies.name, 'Butterflies');
      expect(
        butterflies.anchorLeads.map((s) => s.name).toList(),
        ['Sarah'],
      );
      expect(butterflies.defaultRoom?.id, 'r-main');
      expect(butterflies.childCount, 2);

      final ladybugs = summaries.firstWhere((s) => s.id == 'g-l');
      // Anchor leads sorted by name — Jen before Mike.
      expect(
        ladybugs.anchorLeads.map((s) => s.name).toList(),
        ['Jen', 'Mike'],
      );
      expect(ladybugs.defaultRoom, isNull);
      expect(ladybugs.childCount, 1);
    });

    test('empty db → empty summary list', () async {
      final db = _db();
      addTearDown(db.close);
      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForSummaries(c);
      expect(c.read(groupSummariesProvider).requireValue, isEmpty);
    });

    test('adult with lead role but no anchor is ignored', () async {
      final db = _db();
      addTearDown(db.close);
      await db.into(db.groups).insert(
            GroupsCompanion.insert(id: 'g-b', name: 'Butterflies'),
          );
      await db.into(db.adults).insert(
            AdultsCompanion.insert(
              id: 's-1',
              name: 'Unassigned Lead',
              adultRole: const Value('lead'),
              // anchoredGroupId left null — a lead without a group
              // assignment shouldn't appear on any summary.
            ),
          );

      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForSummaries(c);

      final summaries = c.read(groupSummariesProvider).requireValue;
      expect(summaries.single.anchorLeads, isEmpty);
    });
  });

  group('groupSummaryProvider(id)', () {
    test('returns the matching summary', () async {
      final db = _db();
      addTearDown(db.close);
      await db.into(db.groups).insert(
            GroupsCompanion.insert(id: 'g-b', name: 'Butterflies'),
          );
      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForSummaries(c);
      expect(
        c.read(groupSummaryProvider('g-b')).requireValue?.name,
        'Butterflies',
      );
    });

    test('returns null for an unknown id', () async {
      final db = _db();
      addTearDown(db.close);
      final c = _container(db);
      addTearDown(c.dispose);
      await _waitForSummaries(c);
      expect(c.read(groupSummaryProvider('nope')).requireValue, isNull);
    });
  });
}
