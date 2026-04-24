import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

/// Covers the tag-chip -> filtered archive flow.
///
/// The UI side (tapping a chip, showing the Filtered pill) is small
/// enough to eyeball; what can regress silently is:
///   * the name <-> enum round-trip used to decode the `?tag=` query
///     param into an [ObservationDomain];
///   * the repository's domain-scoped feed, which backs the filtered
///     list once a tag is active.
void main() {
  group('ObservationDomain.fromName', () {
    test('round-trips every known value', () {
      for (final d in ObservationDomain.values) {
        expect(
          ObservationDomain.fromName(d.name),
          d,
          reason: '${d.name} should decode back to $d',
        );
      }
    });

    test('unknown names fall back to .other', () {
      expect(ObservationDomain.fromName('not-a-real-domain'),
          ObservationDomain.other);
      expect(ObservationDomain.fromName(''), ObservationDomain.other);
    });
  });

  group('watchObservationsWithDomain', () {
    late AppDatabase db;
    late ObservationsRepository obs;

    setUp(() {
      db = createTestDatabase();
      obs = ObservationsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('returns only observations tagged with the given domain', () async {
      final empathyId = await obs.addObservation(
        domains: [ObservationDomain.ssd3],
        sentiment: ObservationSentiment.positive,
        note: 'Shared snacks',
      );
      final multiId = await obs.addObservation(
        // Multi-tagged: SSD3 still matches via the join table even when
        // it isn't the primary (legacy) domain.
        domains: [ObservationDomain.ssd1, ObservationDomain.ssd3],
        sentiment: ObservationSentiment.positive,
        note: 'Shared and connected',
      );
      await obs.addObservation(
        domains: [ObservationDomain.hlth1],
        sentiment: ObservationSentiment.neutral,
        note: 'Safety brief',
      );

      final feed =
          await obs.watchObservationsWithDomain(ObservationDomain.ssd3).first;
      final ids = feed.map((o) => o.id).toSet();

      expect(ids, containsAll([empathyId, multiId]));
      expect(ids.length, 2);
    });

    test('empty list when no observation carries the domain', () async {
      await obs.addObservation(
        domains: [ObservationDomain.ssd1],
        sentiment: ObservationSentiment.positive,
        note: 'Unrelated',
      );

      final feed =
          await obs.watchObservationsWithDomain(ObservationDomain.hlth4).first;
      expect(feed, isEmpty);
    });
  });
}
