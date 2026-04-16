import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ObservationDomain {
  social,
  physical,
  creative,
  cognitive,
  behavior,
  milestone,
  other;

  String get label => switch (this) {
        ObservationDomain.social => 'Social',
        ObservationDomain.physical => 'Physical',
        ObservationDomain.creative => 'Creative',
        ObservationDomain.cognitive => 'Cognitive',
        ObservationDomain.behavior => 'Behavior',
        ObservationDomain.milestone => 'Milestone',
        ObservationDomain.other => 'Other',
      };

  static ObservationDomain fromName(String name) {
    return ObservationDomain.values.firstWhere(
      (d) => d.name == name,
      orElse: () => ObservationDomain.other,
    );
  }
}

enum ObservationSentiment {
  positive,
  neutral,
  concern;

  String get label => switch (this) {
        ObservationSentiment.positive => 'Positive',
        ObservationSentiment.neutral => 'Neutral',
        ObservationSentiment.concern => 'Concern',
      };

  static ObservationSentiment fromName(String name) {
    return ObservationSentiment.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ObservationSentiment.neutral,
    );
  }
}

class ObservationsRepository {
  ObservationsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Observation>> watchAll() {
    final query = _db.select(_db.observations)
      ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]);
    return query.watch();
  }

  Stream<List<Observation>> watchForKid(String kidId) {
    final query = _db.select(_db.observations)
      ..where((o) => o.kidId.equals(kidId))
      ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]);
    return query.watch();
  }

  Future<String> addObservation({
    required String targetKind,
    required ObservationDomain domain,
    required ObservationSentiment sentiment,
    required String note,
    String? kidId,
    String? podId,
    String? activityLabel,
    String? tripId,
    String? authorName,
  }) async {
    final id = newId();
    await _db.into(_db.observations).insert(
          ObservationsCompanion.insert(
            id: id,
            targetKind: targetKind,
            kidId: Value(kidId),
            podId: Value(podId),
            activityLabel: Value(activityLabel),
            domain: domain.name,
            sentiment: sentiment.name,
            note: note,
            tripId: Value(tripId),
            authorName: Value(authorName),
          ),
        );
    return id;
  }

  Future<void> deleteObservation(String id) async {
    await (_db.delete(_db.observations)..where((o) => o.id.equals(id))).go();
  }
}

final observationsRepositoryProvider =
    Provider<ObservationsRepository>((ref) {
  return ObservationsRepository(ref.watch(databaseProvider));
});

final observationsProvider = StreamProvider<List<Observation>>((ref) {
  return ref.watch(observationsRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final kidObservationsProvider =
    StreamProvider.family<List<Observation>, String>((ref, kidId) {
  return ref.watch(observationsRepositoryProvider).watchForKid(kidId);
});
