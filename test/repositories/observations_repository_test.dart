import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ObservationsRepository obs;
  late ChildrenRepository kids;

  setUp(() {
    db = createTestDatabase();
    obs = ObservationsRepository(db);
    kids = ChildrenRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CRUD', () {
    test('addObservation persists note + domains + sentiment', () async {
      final id = await obs.addObservation(
        domains: [ObservationDomain.ssd1, ObservationDomain.ssd3],
        sentiment: ObservationSentiment.positive,
        note: 'Maya shared snacks.',
      );
      final all = await obs.watchAll().first;
      expect(all, hasLength(1));
      expect(all.single.id, id);
      expect(all.single.note, 'Maya shared snacks.');
      expect(all.single.sentiment, 'positive');
      // Primary (first-selected) domain is also written to the legacy
      // single column so older queries keep working.
      expect(all.single.domain, 'ssd1');

      final domains = await obs.domainsForObservation(id);
      expect(domains, equals([ObservationDomain.ssd1, ObservationDomain.ssd3]));
    });

    test('addObservation with childIds creates join rows', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final maya = await kids.addChild(firstName: 'Maya', groupId: g);
      final leo = await kids.addChild(firstName: 'Leo', groupId: g);
      final id = await obs.addObservation(
        domains: [ObservationDomain.ssd8],
        sentiment: ObservationSentiment.positive,
        note: 'Played together',
        childIds: [maya, leo],
      );
      final children = await obs.childrenForObservation(id);
      expect(children.map((c) => c.id), containsAll([maya, leo]));
    });

    test('updateObservation replaces childIds wholesale', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final maya = await kids.addChild(firstName: 'Maya', groupId: g);
      final leo = await kids.addChild(firstName: 'Leo', groupId: g);
      final jordan = await kids.addChild(firstName: 'Jordan', groupId: g);

      final id = await obs.addObservation(
        domains: [ObservationDomain.ssd8],
        sentiment: ObservationSentiment.neutral,
        note: 'Play',
        childIds: [maya, leo],
      );
      await obs.updateObservation(id: id, childIds: [jordan]);
      final now = await obs.childrenForObservation(id);
      expect(now.map((c) => c.id), [jordan]);
    });
  });

  group('noteOriginal preserve-across-save (refine round-trip)', () {
    test('updateObservation with noteOriginal sets the column', () async {
      final id = await obs.addObservation(
        domains: [ObservationDomain.ssd1],
        sentiment: ObservationSentiment.neutral,
        note: 'she ate',
      );
      await obs.updateObservation(
        id: id,
        note: 'She ate her snacks happily.',
        noteOriginal: 'she ate',
      );
      final row = await (db.select(db.observations)
            ..where((o) => o.id.equals(id)))
          .getSingle();
      expect(row.note, 'She ate her snacks happily.');
      expect(row.noteOriginal, 'she ate');
    });

    test('clearNoteOriginal wipes the column', () async {
      final id = await obs.addObservation(
        domains: [ObservationDomain.ssd1],
        sentiment: ObservationSentiment.neutral,
        note: 'refined',
        noteOriginal: 'raw',
      );
      await obs.updateObservation(id: id, clearNoteOriginal: true);
      final row = await (db.select(db.observations)
            ..where((o) => o.id.equals(id)))
          .getSingle();
      expect(row.noteOriginal, isNull);
    });

    test('noteOriginal=null + clearNoteOriginal=false leaves column '
        'untouched', () async {
      final id = await obs.addObservation(
        domains: [ObservationDomain.ssd1],
        sentiment: ObservationSentiment.neutral,
        note: 'refined',
        noteOriginal: 'raw',
      );
      await obs.updateObservation(id: id, note: 'still refined');
      final row = await (db.select(db.observations)
            ..where((o) => o.id.equals(id)))
          .getSingle();
      expect(row.noteOriginal, 'raw',
          reason: 'Partial update must not overwrite noteOriginal unless '
              'the caller opts in via clearNoteOriginal or passes a '
              'new value.');
    });
  });

  group('today activity counts (Today screen roll-up)', () {
    test('watchActivityCountsForDay buckets by activityLabel', () async {
      await obs.addObservation(
        domains: [ObservationDomain.ssd1],
        sentiment: ObservationSentiment.positive,
        note: 'a',
        activityLabel: 'Morning Circle',
      );
      await obs.addObservation(
        domains: [ObservationDomain.ssd1],
        sentiment: ObservationSentiment.positive,
        note: 'b',
        activityLabel: 'Morning Circle',
      );
      await obs.addObservation(
        domains: [ObservationDomain.ssd1],
        sentiment: ObservationSentiment.positive,
        note: 'c',
        activityLabel: 'Snack',
      );
      await obs.addObservation(
        domains: [ObservationDomain.ssd1],
        sentiment: ObservationSentiment.positive,
        note: 'unlabeled',
      );
      final counts = await obs.watchActivityCountsForDay(DateTime.now()).first;
      expect(counts['Morning Circle'], 2);
      expect(counts['Snack'], 1);
      expect(counts.containsKey(null), isFalse);
    });
  });

  group('FK cascade: deleting a child cleans up tag rows', () {
    test('deleteChild drops the observation_children row', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final maya = await kids.addChild(firstName: 'Maya', groupId: g);
      final id = await obs.addObservation(
        domains: [ObservationDomain.ssd3],
        sentiment: ObservationSentiment.positive,
        note: 'shared',
        childIds: [maya],
      );
      expect(await obs.childrenForObservation(id), hasLength(1));

      await kids.deleteChild(maya);

      final after = await obs.childrenForObservation(id);
      expect(after, isEmpty,
          reason: 'FK cascade clears tags for deleted children — this '
              'is what keeps stale names out of the edit sheet.');
    });
  });

  group('deleteObservations bulk', () {
    test('bulk delete removes rows + their attachments/tags', () async {
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        ids.add(await obs.addObservation(
          domains: [ObservationDomain.ssd1],
          sentiment: ObservationSentiment.positive,
          note: 'obs $i',
        ));
      }
      expect(await obs.watchAll().first, hasLength(3));
      await obs.deleteObservations([ids[0], ids[2]]);
      final remaining = await obs.watchAll().first;
      expect(remaining.map((o) => o.id), [ids[1]]);
    });
  });
}
