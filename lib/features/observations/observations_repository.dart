import 'dart:io';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
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

  /// Count of observations logged today, bucketed by activity label.
  /// Keys are the raw `activityLabel` string exactly as stored — callers
  /// match against schedule item titles.
  ///
  /// Observations with no activity label aren't counted (they're not
  /// attached to any specific slot). Rebuilds when any observation for
  /// the given day changes.
  Stream<Map<String, int>> watchActivityCountsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final query = _db.select(_db.observations)
      ..where(
        (o) =>
            o.createdAt.isBiggerOrEqualValue(start) &
            o.createdAt.isSmallerThanValue(end) &
            o.activityLabel.isNotNull(),
      );
    return query.watch().map((rows) {
      final map = <String, int>{};
      for (final r in rows) {
        final label = r.activityLabel;
        if (label == null || label.isEmpty) continue;
        map[label] = (map[label] ?? 0) + 1;
      }
      return map;
    });
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

  /// Stream version so cards re-render when an edit sheet changes the
  /// tagged kids. Drift picks up writes to either `observation_kids` or
  /// `kids` and replays the join.
  Stream<List<Kid>> watchKidsForObservation(String observationId) {
    final query = _db.select(_db.kids).join([
      innerJoin(
        _db.observationKids,
        _db.observationKids.kidId.equalsExp(_db.kids.id),
      ),
    ])
      ..where(_db.observationKids.observationId.equals(observationId))
      ..orderBy([OrderingTerm.asc(_db.kids.firstName)]);
    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(_db.kids)).toList());
  }

  Future<String> addObservation({
    required List<ObservationDomain> domains,
    required ObservationSentiment sentiment,
    required String note,
    List<String> kidIds = const [],
    List<ObservationAttachmentInput> attachments = const [],
    String? podId,
    String? activityLabel,
    String? tripId,
    String? authorName,
    // When the teacher saved an AI-refined note, [noteOriginal] holds the
    // pre-refine text so the edit sheet can still flip back to it.
    String? noteOriginal,
  }) async {
    assert(
      domains.isNotEmpty,
      'addObservation requires at least one domain',
    );
    final id = newId();
    final targetKind = kidIds.isNotEmpty
        ? 'kids'
        : podId != null
            ? 'pod'
            : activityLabel != null && activityLabel.isNotEmpty
                ? 'activity'
                : 'general';

    // Dedupe while preserving caller order — the first domain is the
    // "primary" and flows through to the legacy column.
    final uniqueDomains = <ObservationDomain>{...domains}.toList();
    final primary = uniqueDomains.first;

    await _db.transaction(() async {
      await _db.into(_db.observations).insert(
            ObservationsCompanion.insert(
              id: id,
              targetKind: targetKind,
              podId: Value(podId),
              activityLabel: Value(activityLabel),
              domain: primary.name,
              sentiment: sentiment.name,
              note: note,
              noteOriginal: Value(noteOriginal),
              tripId: Value(tripId),
              authorName: Value(authorName),
            ),
          );
      for (final d in uniqueDomains) {
        await _db.into(_db.observationDomainTags).insert(
              ObservationDomainTagsCompanion.insert(
                observationId: id,
                domain: d.name,
              ),
            );
      }
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

  /// Domains tagged on an observation, in insertion order. Falls back to
  /// the legacy single-column value when no join rows exist (shouldn't
  /// happen post-migration but kept as a defensive default).
  Future<List<ObservationDomain>> domainsForObservation(
    String observationId,
  ) async {
    final rows = await (_db.select(_db.observationDomainTags)
          ..where((d) => d.observationId.equals(observationId)))
        .get();
    if (rows.isEmpty) return const [];
    return rows.map((r) => ObservationDomain.fromName(r.domain)).toList();
  }

  /// Stream version for live-updating cards and edit sheets.
  Stream<List<ObservationDomain>> watchDomainsForObservation(
    String observationId,
  ) {
    return (_db.select(_db.observationDomainTags)
          ..where((d) => d.observationId.equals(observationId)))
        .watch()
        .map(
          (rows) =>
              rows.map((r) => ObservationDomain.fromName(r.domain)).toList(),
        );
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

  /// Watch every attachment in the DB, newest first. Feeds the
  /// media-only filter on the Observe tab.
  Stream<List<ObservationAttachment>> watchAllAttachments() {
    return (_db.select(_db.observationAttachments)
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
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
    // Pull the path before the row goes away so the on-disk file can
    // be cleaned up too — the DB delete alone would leak megabytes of
    // photos and videos.
    final row = await (_db.select(_db.observationAttachments)
          ..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.observationAttachments)
          ..where((a) => a.id.equals(id)))
        .go();
    if (row != null) await _deleteLocalFile(row.localPath);
  }

  /// Best-effort removal of a local media file. Swallows every error
  /// on purpose — a stale path, a permissions hiccup, or web (no
  /// dart:io) shouldn't block a DB delete the user has already
  /// confirmed.
  Future<void> _deleteLocalFile(String path) async {
    if (kIsWeb) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on Object {
      // swallow
    }
  }

  /// Partial update. Anything left as `null` (or not passed) is left
  /// untouched in the row. Kid tagging is replaced wholesale when
  /// [kidIds] is non-null; pass `const []` to clear. Same for [domains] —
  /// pass a non-empty list to replace, null to leave alone.
  Future<void> updateObservation({
    required String id,
    String? note,
    // The pre-refine text to preserve when the refined version is in use.
    // Pass the string to set it, or set [clearNoteOriginal] to drop it
    // (teacher reverted to the original, or never refined).
    String? noteOriginal,
    bool clearNoteOriginal = false,
    List<ObservationDomain>? domains,
    ObservationSentiment? sentiment,
    List<String>? kidIds,
    String? podId,
    bool clearPodId = false,
    String? activityLabel,
    bool clearActivityLabel = false,
  }) async {
    final uniqueDomains = domains == null
        ? null
        : <ObservationDomain>{...domains}.toList();
    final primaryDomain = (uniqueDomains == null || uniqueDomains.isEmpty)
        ? null
        : uniqueDomains.first;

    await _db.transaction(() async {
      final companion = ObservationsCompanion(
        note: note == null ? const Value.absent() : Value(note),
        noteOriginal: clearNoteOriginal
            ? const Value<String?>(null)
            : (noteOriginal == null
                ? const Value.absent()
                : Value(noteOriginal)),
        domain: primaryDomain == null
            ? const Value.absent()
            : Value(primaryDomain.name),
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

      if (uniqueDomains != null && uniqueDomains.isNotEmpty) {
        await (_db.delete(_db.observationDomainTags)
              ..where((d) => d.observationId.equals(id)))
            .go();
        for (final d in uniqueDomains) {
          await _db.into(_db.observationDomainTags).insert(
                ObservationDomainTagsCompanion.insert(
                  observationId: id,
                  domain: d.name,
                ),
              );
        }
      }
    });
  }

  Future<void> deleteObservation(String id) async {
    // Grab every attachment's path before we drop the row — once the
    // observation goes the FK cascade nukes the attachment rows, but
    // the local media files are ours to clean up explicitly.
    final attachments = await (_db.select(_db.observationAttachments)
          ..where((a) => a.observationId.equals(id)))
        .get();
    await (_db.delete(_db.observations)..where((o) => o.id.equals(id))).go();
    for (final a in attachments) {
      await _deleteLocalFile(a.localPath);
    }
  }

  /// Batch version. Groups the DB delete into a single `WHERE id IN`
  /// so the stream providers only emit once, then fires a best-effort
  /// file cleanup for every attachment in the removed set.
  Future<void> deleteObservations(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final attachments = await (_db.select(_db.observationAttachments)
          ..where((a) => a.observationId.isIn(list)))
        .get();
    await (_db.delete(_db.observations)..where((o) => o.id.isIn(list)))
        .go();
    for (final a in attachments) {
      await _deleteLocalFile(a.localPath);
    }
  }

  /// Batch version of [deleteAttachment]. One DB delete, plus a file
  /// cleanup per path — same shape as [deleteObservations].
  Future<void> deleteAttachments(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final rows = await (_db.select(_db.observationAttachments)
          ..where((a) => a.id.isIn(list)))
        .get();
    await (_db.delete(_db.observationAttachments)
          ..where((a) => a.id.isIn(list)))
        .go();
    for (final r in rows) {
      await _deleteLocalFile(r.localPath);
    }
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

/// Today's observation counts keyed by `activityLabel` — the Today
/// screen uses this to decide whether to show a "Log observations →"
/// nudge on activities that have already ended.
///
/// Deliberately snapshots `DateTime.now()` once at provider creation;
/// the app is re-launched over midnight in practice so rollover is not
/// a concern worth the extra wiring.
final todayActivityCountsProvider =
    StreamProvider<Map<String, int>>((ref) {
  return ref
      .watch(observationsRepositoryProvider)
      .watchActivityCountsForDay(DateTime.now());
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
    StreamProvider.family<List<Kid>, String>((ref, observationId) {
  return ref
      .watch(observationsRepositoryProvider)
      .watchKidsForObservation(observationId);
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

/// Every attachment across every observation — the Observe tab's media
/// filter shows these in a grid.
final allAttachmentsProvider =
    StreamProvider<List<ObservationAttachment>>((ref) {
  return ref.watch(observationsRepositoryProvider).watchAllAttachments();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final observationDomainsProvider =
    StreamProvider.family<List<ObservationDomain>, String>(
        (ref, observationId) {
  return ref
      .watch(observationsRepositoryProvider)
      .watchDomainsForObservation(observationId);
});
