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
    // Pulls observations via the join table (multi-kid) PLUS any legacy
    // single-kid rows where kidId matches.
    final joinQuery = _db.select(_db.observations).join([
      innerJoin(
        _db.observationKids,
        _db.observationKids.observationId.equalsExp(_db.observations.id),
      ),
    ])
      ..where(_db.observationKids.kidId.equals(kidId))
      ..orderBy([OrderingTerm.desc(_db.observations.createdAt)]);

    return joinQuery.watch().map(
          (rows) => rows.map((r) => r.readTable(_db.observations)).toList(),
        );
  }

  Future<List<Kid>> kidsForObservation(String observationId) async {
    final rows = await (_db.select(_db.kids).join([
      innerJoin(
        _db.observationKids,
        _db.observationKids.kidId.equalsExp(_db.kids.id),
      ),
    ])
          ..where(_db.observationKids.observationId.equals(observationId))
          ..orderBy([OrderingTerm.asc(_db.kids.firstName)]))
        .get();
    return rows.map((r) => r.readTable(_db.kids)).toList();
  }

  Future<String> addObservation({
    required ObservationDomain domain,
    required ObservationSentiment sentiment,
    required String note,
    List<String> kidIds = const [],
    List<ObservationAttachmentInput> attachments = const [],
    String? podId,
    String? activityLabel,
    String? tripId,
    String? authorName,
  }) async {
    final id = newId();
    final targetKind = kidIds.isNotEmpty
        ? 'kids'
        : podId != null
            ? 'pod'
            : activityLabel != null && activityLabel.isNotEmpty
                ? 'activity'
                : 'general';

    await _db.transaction(() async {
      await _db.into(_db.observations).insert(
            ObservationsCompanion.insert(
              id: id,
              targetKind: targetKind,
              podId: Value(podId),
              activityLabel: Value(activityLabel),
              domain: domain.name,
              sentiment: sentiment.name,
              note: note,
              tripId: Value(tripId),
              authorName: Value(authorName),
            ),
          );
      for (final kidId in kidIds) {
        await _db.into(_db.observationKids).insert(
              ObservationKidsCompanion.insert(
                observationId: id,
                kidId: kidId,
              ),
            );
      }
      for (final att in attachments) {
        await _db.into(_db.observationAttachments).insert(
              ObservationAttachmentsCompanion.insert(
                id: newId(),
                observationId: id,
                kind: att.kind,
                localPath: att.localPath,
                durationMs: Value(att.durationMs),
              ),
            );
      }
    });
    return id;
  }

  Future<List<ObservationAttachment>> attachmentsForObservation(
    String observationId,
  ) {
    return (_db.select(_db.observationAttachments)
          ..where((a) => a.observationId.equals(observationId))
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .get();
  }

  Future<void> deleteObservation(String id) async {
    await (_db.delete(_db.observations)..where((o) => o.id.equals(id))).go();
  }
}

/// Minimal descriptor used when creating an observation. Local-first:
/// the file path points at a device path. Remote upload happens later.
class ObservationAttachmentInput {
  const ObservationAttachmentInput({
    required this.kind,
    required this.localPath,
    this.durationMs,
  });

  /// 'photo' or 'video'.
  final String kind;
  final String localPath;
  final int? durationMs;
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

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final observationKidsProvider =
    FutureProvider.family<List<Kid>, String>((ref, observationId) {
  return ref
      .watch(observationsRepositoryProvider)
      .kidsForObservation(observationId);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final observationAttachmentsProvider =
    FutureProvider.family<List<ObservationAttachment>, String>(
        (ref, observationId) {
  return ref
      .watch(observationsRepositoryProvider)
      .attachmentsForObservation(observationId);
});
