import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Domains that align with the program's observation taxonomy.
/// The SSD* values cover social & self-development; HLTH* cover health.
enum ObservationDomain {
  ssd1,
  ssd2,
  ssd3,
  ssd4,
  ssd5,
  ssd6,
  ssd7,
  ssd8,
  ssd9,
  hlth1,
  hlth2,
  hlth3,
  hlth4,
  other;

  /// Compact curriculum code for display ("SSD1", "HLTH3", etc.).
  String get code => switch (this) {
        ObservationDomain.ssd1 => 'SSD1',
        ObservationDomain.ssd2 => 'SSD2',
        ObservationDomain.ssd3 => 'SSD3',
        ObservationDomain.ssd4 => 'SSD4',
        ObservationDomain.ssd5 => 'SSD5',
        ObservationDomain.ssd6 => 'SSD6',
        ObservationDomain.ssd7 => 'SSD7',
        ObservationDomain.ssd8 => 'SSD8',
        ObservationDomain.ssd9 => 'SSD9',
        ObservationDomain.hlth1 => 'HLTH1',
        ObservationDomain.hlth2 => 'HLTH2',
        ObservationDomain.hlth3 => 'HLTH3',
        ObservationDomain.hlth4 => 'HLTH4',
        ObservationDomain.other => '—',
      };

  /// Short human label — the one used on chips and cards.
  String get label => switch (this) {
        ObservationDomain.ssd1 => 'Identity & connection',
        ObservationDomain.ssd2 => 'Self-esteem',
        ObservationDomain.ssd3 => 'Empathy',
        ObservationDomain.ssd4 => 'Impulse control',
        ObservationDomain.ssd5 => 'Follow rules',
        ObservationDomain.ssd6 => 'Awareness of diversity',
        ObservationDomain.ssd7 => 'Interactions with adults',
        ObservationDomain.ssd8 => 'Friendship',
        ObservationDomain.ssd9 => 'Conflict negotiation',
        ObservationDomain.hlth1 => 'Safety',
        ObservationDomain.hlth2 => 'Healthy lifestyle',
        ObservationDomain.hlth3 => 'Personal care routine',
        ObservationDomain.hlth4 => 'Exercise & fitness',
        ObservationDomain.other => 'Other',
      };

  /// Group for section headers in pickers.
  ObservationDomainCategory get category => switch (this) {
        ObservationDomain.ssd1 ||
        ObservationDomain.ssd2 ||
        ObservationDomain.ssd3 ||
        ObservationDomain.ssd4 ||
        ObservationDomain.ssd5 ||
        ObservationDomain.ssd6 ||
        ObservationDomain.ssd7 ||
        ObservationDomain.ssd8 ||
        ObservationDomain.ssd9 =>
          ObservationDomainCategory.socialSelfDev,
        ObservationDomain.hlth1 ||
        ObservationDomain.hlth2 ||
        ObservationDomain.hlth3 ||
        ObservationDomain.hlth4 =>
          ObservationDomainCategory.health,
        ObservationDomain.other => ObservationDomainCategory.other,
      };

  static ObservationDomain fromName(String name) {
    return ObservationDomain.values.firstWhere(
      (d) => d.name == name,
      orElse: () => ObservationDomain.other,
    );
  }
}

enum ObservationDomainCategory {
  socialSelfDev,
  health,
  other;

  String get label => switch (this) {
        ObservationDomainCategory.socialSelfDev =>
          'Social & self-development',
        ObservationDomainCategory.health => 'Health',
        ObservationDomainCategory.other => 'Other',
      };
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

  /// Watch attachments for an observation so the list rebuilds when an
  /// edit adds or removes a photo/video.
  Stream<List<ObservationAttachment>> watchAttachmentsForObservation(
    String observationId,
  ) {
    return (_db.select(_db.observationAttachments)
          ..where((a) => a.observationId.equals(observationId))
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .watch();
  }

  Future<String> addAttachment({
    required String observationId,
    required ObservationAttachmentInput input,
  }) async {
    final id = newId();
    await _db.into(_db.observationAttachments).insert(
          ObservationAttachmentsCompanion.insert(
            id: id,
            observationId: observationId,
            kind: input.kind,
            localPath: input.localPath,
            durationMs: Value(input.durationMs),
          ),
        );
    return id;
  }

  Future<void> deleteAttachment(String id) async {
    await (_db.delete(_db.observationAttachments)
          ..where((a) => a.id.equals(id)))
        .go();
  }

  /// Partial update. Anything left as `null` (or not passed) is left
  /// untouched in the row. Kid tagging is replaced wholesale when
  /// [kidIds] is non-null; pass `const []` to clear.
  Future<void> updateObservation({
    required String id,
    String? note,
    ObservationDomain? domain,
    ObservationSentiment? sentiment,
    List<String>? kidIds,
    String? podId,
    bool clearPodId = false,
    String? activityLabel,
    bool clearActivityLabel = false,
  }) async {
    await _db.transaction(() async {
      final companion = ObservationsCompanion(
        note: note == null ? const Value.absent() : Value(note),
        domain: domain == null ? const Value.absent() : Value(domain.name),
        sentiment:
            sentiment == null ? const Value.absent() : Value(sentiment.name),
        podId: clearPodId
            ? const Value<String?>(null)
            : (podId == null ? const Value.absent() : Value(podId)),
        activityLabel: clearActivityLabel
            ? const Value<String?>(null)
            : (activityLabel == null
                ? const Value.absent()
                : Value(activityLabel)),
        updatedAt: Value(DateTime.now()),
      );
      // Recompute targetKind if the target mix changes.
      String? nextTargetKind;
      if (kidIds != null) {
        nextTargetKind = kidIds.isNotEmpty
            ? 'kids'
            : (clearPodId || podId == null) &&
                    (clearActivityLabel || activityLabel == null)
                ? 'general'
                : null;
      }

      await (_db.update(_db.observations)..where((o) => o.id.equals(id)))
          .write(
        nextTargetKind == null
            ? companion
            : companion.copyWith(targetKind: Value(nextTargetKind)),
      );

      if (kidIds != null) {
        await (_db.delete(_db.observationKids)
              ..where((k) => k.observationId.equals(id)))
            .go();
        for (final kidId in kidIds) {
          await _db.into(_db.observationKids).insert(
                ObservationKidsCompanion.insert(
                  observationId: id,
                  kidId: kidId,
                ),
              );
        }
      }
    });
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
    StreamProvider.family<List<ObservationAttachment>, String>(
        (ref, observationId) {
  return ref
      .watch(observationsRepositoryProvider)
      .watchAttachmentsForObservation(observationId);
});
