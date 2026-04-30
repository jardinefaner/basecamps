import 'dart:async';
import 'dart:io';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/media_service.dart';
import 'package:basecamp/features/sync/observations_sync_service.dart';
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
  ObservationsRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// Active program id, read fresh on every insert. Null while the
  /// auth bootstrap hasn't run yet — rows in that window go in with
  /// program_id NULL and get picked up by the next-launch backfill.
  /// Steady state: every new row is stamped on insert.
  String? get _programId => _ref.read(activeProgramIdProvider);

  /// Slice C push hook. Every mutation (insert / update / delete /
  /// attachment add / attachment delete) fires a fire-and-forget
  /// push to cloud once the local commit lands. The service
  /// catches its own errors so a network blip never trips the
  /// local-write callsite.
  ObservationsSyncService get _sync =>
      _ref.read(observationsSyncServiceProvider);

  /// Media uploader. After every attachment insert we kick a
  /// fire-and-forget upload of the local file to Supabase Storage
  /// so other devices can resolve through the bucket.
  MediaService get _media => _ref.read(mediaServiceProvider);

  Stream<List<Observation>> watchAll() {
    final query = _db.select(_db.observations)
      ..where((o) => matchesActiveProgram(o.programId, _programId))
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
            o.activityLabel.isNotNull() &
            matchesActiveProgram(o.programId, _programId),
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

  /// Observations tagged with [domain], newest first. Drives the
  /// Observe archive's domain-filter pill — tap a chip on any
  /// observation card and land here scoped to that domain.
  ///
  /// Uses the join table (`observation_domain_tags`) so observations
  /// tagged across multiple domains still surface when any one of
  /// them matches. The legacy single `domain` column isn't consulted
  /// directly — post-migration every observation has at least one
  /// join row mirroring it.
  Stream<List<Observation>> watchObservationsWithDomain(
    ObservationDomain domain,
  ) {
    final query = _db.select(_db.observations).join([
      innerJoin(
        _db.observationDomainTags,
        _db.observationDomainTags.observationId.equalsExp(_db.observations.id),
      ),
    ])
      ..where(_db.observationDomainTags.domain.equals(domain.name) &
          matchesActiveProgram(_db.observations.programId, _programId))
      ..orderBy([OrderingTerm.desc(_db.observations.createdAt)]);
    return query.watch().map(
          (rows) => rows.map((r) => r.readTable(_db.observations)).toList(),
        );
  }

  Stream<List<Observation>> watchForKid(String childId) {
    // Pulls observations via the join table (multi-kid) PLUS any legacy
    // single-kid rows where childId matches.
    final joinQuery = _db.select(_db.observations).join([
      innerJoin(
        _db.observationChildren,
        _db.observationChildren.observationId.equalsExp(_db.observations.id),
      ),
    ])
      ..where(_db.observationChildren.childId.equals(childId) &
          matchesActiveProgram(_db.observations.programId, _programId))
      ..orderBy([OrderingTerm.desc(_db.observations.createdAt)]);

    return joinQuery.watch().map(
          (rows) => rows.map((r) => r.readTable(_db.observations)).toList(),
        );
  }

  Future<List<Child>> childrenForObservation(String observationId) async {
    final rows = await (_db.select(_db.children).join([
      innerJoin(
        _db.observationChildren,
        _db.observationChildren.childId.equalsExp(_db.children.id),
      ),
    ])
          ..where(_db.observationChildren.observationId.equals(observationId))
          ..orderBy([OrderingTerm.asc(_db.children.firstName)]))
        .get();
    return rows.map((r) => r.readTable(_db.children)).toList();
  }

  /// Stream version so cards re-render when an edit sheet changes the
  /// tagged kids. Drift picks up writes to either `observation_kids` or
  /// `kids` and replays the join.
  Stream<List<Child>> watchChildrenForObservation(String observationId) {
    final query = _db.select(_db.children).join([
      innerJoin(
        _db.observationChildren,
        _db.observationChildren.childId.equalsExp(_db.children.id),
      ),
    ])
      ..where(_db.observationChildren.observationId.equals(observationId))
      ..orderBy([OrderingTerm.asc(_db.children.firstName)]);
    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(_db.children)).toList());
  }

  Future<String> addObservation({
    required List<ObservationDomain> domains,
    required ObservationSentiment sentiment,
    required String note,
    List<String> childIds = const [],
    List<ObservationAttachmentInput> attachments = const [],
    String? groupId,
    String? activityLabel,
    String? tripId,
    String? authorName,
    // When the teacher saved an AI-refined note, [noteOriginal] holds the
    // pre-refine text so the edit sheet can still flip back to it.
    String? noteOriginal,
    // v33: structural link to the activity occurrence. Callers that
    // capture during a scheduled activity pass these so reports can
    // slice by the exact Morning-Circle-on-April-23-Butterflies
    // instance instead of a free-form activityLabel string.
    String? scheduleSourceKind,
    String? scheduleSourceId,
    DateTime? activityDate,
    String? roomId,
  }) async {
    assert(
      domains.isNotEmpty,
      'addObservation requires at least one domain',
    );
    final id = newId();
    final targetKind = childIds.isNotEmpty
        ? 'kids'
        : groupId != null
            ? 'group'
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
              groupId: Value(groupId),
              activityLabel: Value(activityLabel),
              domain: primary.name,
              sentiment: sentiment.name,
              note: note,
              noteOriginal: Value(noteOriginal),
              tripId: Value(tripId),
              authorName: Value(authorName),
              scheduleSourceKind: Value(scheduleSourceKind),
              scheduleSourceId: Value(scheduleSourceId),
              activityDate: Value(activityDate),
              roomId: Value(roomId),
              programId: Value(_programId),
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
      for (final childId in childIds) {
        await _db.into(_db.observationChildren).insert(
              ObservationChildrenCompanion.insert(
                observationId: id,
                childId: childId,
              ),
            );
      }
      for (final att in attachments) {
        final attachmentId = newId();
        await _db.into(_db.observationAttachments).insert(
              ObservationAttachmentsCompanion.insert(
                id: attachmentId,
                observationId: id,
                kind: att.kind,
                localPath: att.localPath,
                durationMs: Value(att.durationMs),
              ),
            );
        // Fire-and-forget media upload. Stamps storage_path on
        // the row when complete, then the next push picks up the
        // updated row and propagates to other devices.
        unawaited(_media.uploadObservationAttachment(attachmentId));
      }
    });
    // Fire-and-forget cloud push. Failure logs but doesn't block —
    // the local insert already succeeded.
    unawaited(_sync.pushObservation(id));
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
    // Scope through the parent observation — attachments have no
    // programId of their own (cascade table), so we join to
    // observations and filter on the parent's programId.
    final query = _db.select(_db.observationAttachments).join([
      innerJoin(
        _db.observations,
        _db.observations.id
            .equalsExp(_db.observationAttachments.observationId),
      ),
    ])
      ..where(matchesActiveProgram(_db.observations.programId, _programId))
      ..orderBy([
        OrderingTerm.desc(_db.observationAttachments.createdAt),
      ]);
    return query.watch().map(
          (rows) => rows
              .map((r) => r.readTable(_db.observationAttachments))
              .toList(),
        );
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
    // Fire-and-forget media upload. The push that follows picks
    // up the row's eventual storage_path so other devices can
    // resolve through the bucket.
    unawaited(_media.uploadObservationAttachment(id));
    // Push the parent observation so the new cascade row is
    // mirrored to cloud (the service replaces the cascade
    // wholesale, so this picks up the new attachment).
    unawaited(_sync.pushObservation(observationId));
    return id;
  }

  /// Delete a single attachment row. The on-disk media file is
  /// deliberately left in place so an undo snackbar within the 5
  /// second window can restore the row against an intact file —
  /// orphaned files are reaped later by
  /// [sweepOrphanedAttachmentFiles].
  Future<void> deleteAttachment(String id) async {
    final row = await (_db.select(_db.observationAttachments)
          ..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.observationAttachments)
          ..where((a) => a.id.equals(id)))
        .go();
    if (row != null) {
      // Re-push parent observation so cloud's cascade table loses
      // the deleted row too.
      unawaited(_sync.pushObservation(row.observationId));
    }
  }

  /// Partial update. Anything left as `null` (or not passed) is left
  /// untouched in the row. Child tagging is replaced wholesale when
  /// [childIds] is non-null; pass `const []` to clear. Same for [domains] —
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
    List<String>? childIds,
    String? groupId,
    bool clearGroupId = false,
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
        groupId: clearGroupId
            ? const Value<String?>(null)
            : (groupId == null ? const Value.absent() : Value(groupId)),
        activityLabel: clearActivityLabel
            ? const Value<String?>(null)
            : (activityLabel == null
                ? const Value.absent()
                : Value(activityLabel)),
        updatedAt: Value(DateTime.now()),
      );
      // Recompute targetKind if the target mix changes.
      String? nextTargetKind;
      if (childIds != null) {
        nextTargetKind = childIds.isNotEmpty
            ? 'kids'
            : (clearGroupId || groupId == null) &&
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

      if (childIds != null) {
        await (_db.delete(_db.observationChildren)
              ..where((k) => k.observationId.equals(id)))
            .go();
        for (final childId in childIds) {
          await _db.into(_db.observationChildren).insert(
                ObservationChildrenCompanion.insert(
                  observationId: id,
                  childId: childId,
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
    await _db.markDirty('observations', id, [
      if (note != null) 'note',
      if (clearNoteOriginal || noteOriginal != null) 'note_original',
      if (primaryDomain != null) 'domain',
      if (sentiment != null) 'sentiment',
      if (clearGroupId || groupId != null) 'group_id',
      if (clearActivityLabel || activityLabel != null) 'activity_label',
      if (childIds != null) 'target_kind',
    ]);
    unawaited(_sync.pushObservation(id));
  }

  /// Captures everything that CASCADE would wipe on delete, so the
  /// undo snackbar can restore the observation with its joins intact.
  /// Doesn't touch the DB — it's a pre-delete read.
  Future<ObservationSnapshot> snapshotObservation(String id) async {
    final observation = await (_db.select(_db.observations)
          ..where((o) => o.id.equals(id)))
        .getSingleOrNull();
    if (observation == null) {
      return const ObservationSnapshot.empty();
    }
    final childLinks = await (_db.select(_db.observationChildren)
          ..where((c) => c.observationId.equals(id)))
        .get();
    final attachments = await (_db.select(_db.observationAttachments)
          ..where((a) => a.observationId.equals(id)))
        .get();
    final tags = await (_db.select(_db.observationDomainTags)
          ..where((t) => t.observationId.equals(id)))
        .get();
    return ObservationSnapshot(
      observations: [observation],
      childLinks: childLinks,
      attachments: attachments,
      tags: tags,
    );
  }

  /// Batch snapshot for bulk delete. Single roundtrip per join table.
  Future<ObservationSnapshot> snapshotObservations(
    Iterable<String> ids,
  ) async {
    final list = ids.toList();
    if (list.isEmpty) return const ObservationSnapshot.empty();
    final observations = await (_db.select(_db.observations)
          ..where((o) => o.id.isIn(list)))
        .get();
    final childLinks = await (_db.select(_db.observationChildren)
          ..where((c) => c.observationId.isIn(list)))
        .get();
    final attachments = await (_db.select(_db.observationAttachments)
          ..where((a) => a.observationId.isIn(list)))
        .get();
    final tags = await (_db.select(_db.observationDomainTags)
          ..where((t) => t.observationId.isIn(list)))
        .get();
    return ObservationSnapshot(
      observations: observations,
      childLinks: childLinks,
      attachments: attachments,
      tags: tags,
    );
  }

  /// Drops the observation row. CASCADE wipes domain tags, child
  /// links, and attachment rows; the LOCAL FILES are deliberately
  /// left alone so an undo within the snackbar window can restore
  /// everything — attachment files live on disk until the orphan
  /// sweeper reaps them (see [sweepOrphanedAttachmentFiles]).
  Future<void> deleteObservation(String id) async {
    // Capture program before the row goes away — pushDelete needs
    // the program_id and we can't read it once the row's gone.
    final row = await (_db.select(_db.observations)
          ..where((o) => o.id.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.observations)..where((o) => o.id.equals(id))).go();
    final programId = row?.programId;
    if (programId != null) {
      unawaited(_sync.pushDelete(observationId: id, programId: programId));
    }
  }

  /// Batch version. Groups the DB delete into a single `WHERE id IN`
  /// so the stream providers only emit once. Files stay on disk —
  /// swept later.
  Future<void> deleteObservations(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    // Capture program ids before the rows are gone so each delete
    // can be soft-deleted in cloud. Group by id since each row may
    // belong to a different program (rare but possible if the
    // teacher switches programs between observations).
    final rows = await (_db.select(_db.observations)
          ..where((o) => o.id.isIn(list)))
        .get();
    await (_db.delete(_db.observations)..where((o) => o.id.isIn(list)))
        .go();
    for (final r in rows) {
      final programId = r.programId;
      if (programId != null) {
        unawaited(
          _sync.pushDelete(observationId: r.id, programId: programId),
        );
      }
    }
  }

  /// Re-inserts an observation (or a batch of them) + every join row
  /// the snapshot captured. Used by the undo snackbar.
  Future<void> restoreObservations(ObservationSnapshot snap) async {
    await _db.transaction(() async {
      for (final o in snap.observations) {
        await _db.into(_db.observations).insertOnConflictUpdate(o);
      }
      for (final t in snap.tags) {
        await _db.into(_db.observationDomainTags).insertOnConflictUpdate(t);
      }
      for (final c in snap.childLinks) {
        await _db
            .into(_db.observationChildren)
            .insertOnConflictUpdate(c);
      }
      for (final a in snap.attachments) {
        await _db
            .into(_db.observationAttachments)
            .insertOnConflictUpdate(a);
      }
    });
    // Re-push to cloud. Restore can come from the undo snackbar
    // *after* a delete pushed deleted_at to cloud — the next push
    // overwrites the row (without deleted_at, since the serializer
    // omits that field) and other devices learn it's back.
    for (final o in snap.observations) {
      unawaited(_sync.pushObservation(o.id));
    }
  }

  /// Delete attachment rows without touching the on-disk files. Used
  /// by the attachment viewer when a teacher removes a single photo
  /// or video — file cleanup is deferred to the orphan sweeper so
  /// undo can restore the row against an intact file.
  Future<void> deleteAttachments(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(_db.observationAttachments)
          ..where((a) => a.id.isIn(list)))
        .go();
  }

  /// Snapshot (+ restore) for single attachment deletes.
  Future<List<ObservationAttachment>> snapshotAttachments(
    Iterable<String> ids,
  ) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value(const []);
    return (_db.select(_db.observationAttachments)
          ..where((a) => a.id.isIn(list)))
        .get();
  }

  Future<void> restoreAttachments(
    Iterable<ObservationAttachment> rows,
  ) async {
    await _db.transaction(() async {
      for (final r in rows) {
        await _db
            .into(_db.observationAttachments)
            .insertOnConflictUpdate(r);
      }
    });
    final observationIds = {for (final r in rows) r.observationId};
    for (final id in observationIds) {
      unawaited(_sync.pushObservation(id));
    }
  }

  /// Sweeps local media files that no attachment row points at.
  /// Designed to be called on app startup — reaps orphans left
  /// behind by undo-enabled deletes that weren't undone within
  /// the snackbar window. Safe to run any time.
  ///
  /// Scans only the files currently referenced vs. the app-owned
  /// media directory. Anything outside that dir (user-picked photo
  /// paths, camera-roll shares) is left alone — not ours to delete.
  Future<int> sweepOrphanedAttachmentFiles({
    required Directory mediaDir,
  }) async {
    if (kIsWeb) return 0;
    if (!mediaDir.existsSync()) return 0;
    final referenced = await _db
        .select(_db.observationAttachments)
        .get()
        .then((rows) => rows.map((r) => r.localPath).toSet());
    var swept = 0;
    try {
      final entries = mediaDir.listSync(followLinks: false);
      for (final e in entries) {
        if (e is! File) continue;
        if (referenced.contains(e.path)) continue;
        try {
          e.deleteSync();
          swept++;
        } on Object {
          // Ignore — stale handle, permission, etc. Sweep again
          // next launch.
        }
      }
    } on Object {
      // Directory may have vanished or been replaced mid-scan.
      // Not a hard error.
    }
    return swept;
  }
}

/// Bundle of rows captured before an observation delete — the
/// observation itself plus every CASCADE-wiped join row. Used by the
/// undo snackbar's restore callback so every side of the observation
/// (tags, child links, attachments) comes back together.
class ObservationSnapshot {
  const ObservationSnapshot({
    required this.observations,
    required this.childLinks,
    required this.attachments,
    required this.tags,
  });

  const ObservationSnapshot.empty()
      : observations = const [],
        childLinks = const [],
        attachments = const [],
        tags = const [];

  final List<Observation> observations;
  final List<ObservationChildrenData> childLinks;
  final List<ObservationAttachment> attachments;
  final List<ObservationDomainTag> tags;

  bool get isEmpty => observations.isEmpty;
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
  return ObservationsRepository(ref.watch(databaseProvider), ref);
});

final observationsProvider = StreamProvider<List<Observation>>((ref) {
  ref.watch(activeProgramIdProvider);
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
  ref.watch(activeProgramIdProvider);
  return ref
      .watch(observationsRepositoryProvider)
      .watchActivityCountsForDay(DateTime.now());
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final observationsWithDomainProvider =
    StreamProvider.family<List<Observation>, ObservationDomain>((ref, domain) {
  ref.watch(activeProgramIdProvider);
  return ref
      .watch(observationsRepositoryProvider)
      .watchObservationsWithDomain(domain);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final childObservationsProvider =
    StreamProvider.family<List<Observation>, String>((ref, childId) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(observationsRepositoryProvider).watchForKid(childId);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final observationChildrenProvider =
    StreamProvider.family<List<Child>, String>((ref, observationId) {
  return ref
      .watch(observationsRepositoryProvider)
      .watchChildrenForObservation(observationId);
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
  ref.watch(activeProgramIdProvider);
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
