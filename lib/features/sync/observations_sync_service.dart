import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push + pull sync for the Observations table and its cascade rows.
///
/// **Push:** every local write to ObservationsRepository fires a
/// best-effort push to Supabase Postgres (fire-and-forget). The
/// service catches its own errors so a network blip never trips the
/// local write.
///
/// **Pull:** [pullObservations] runs on sign-in (and on a manual
/// "Sync now" button). It's incremental and watermarked — only
/// fetches rows with `updated_at` newer than the local
/// `sync_state` watermark for this (program, observations) pair.
/// First pull on a fresh device uses the epoch watermark so it
/// downloads everything once; subsequent pulls fetch deltas only.
///
/// Cost shape:
///   - Page size capped at [_kPageSize] rows per query, looped on
///     overflow. Bounded bandwidth per call.
///   - Debounced via [_kPullDebounce] — skip if the last
///     successful pull was within that window.
///   - One round-trip per cascade table (children, attachments,
///     domain_tags) per page, batched by the parent's id list.
///   - The (program_id, updated_at) cloud-side index keeps the
///     watermark filter cheap regardless of table size.
///
/// Why fire-and-forget instead of awaited:
///   - Local UX should never wait on a network round-trip. Saving
///     an observation feels instant; the cloud catches up in the
///     background.
///   - A failed push is recoverable: any later edit to the same
///     row pushes the full updated state, which is functionally
///     equivalent to a retry. No queue infrastructure needed for
///     v1.
///   - "Last write wins by updated_at" is the conflict model, and
///     the cloud trigger bumps updated_at on receipt, so a stale
///     push never clobbers a fresher one.
class ObservationsSyncService {
  ObservationsSyncService(this._db);

  final AppDatabase _db;

  /// Cap rows fetched per round-trip. Bounded bandwidth per call,
  /// plus predictable memory use on large programs. When a page
  /// returns this many rows we know there might be more and loop
  /// until a short page comes back. 500 is a reasonable sweet
  /// spot — small enough to fit in a single ~250KB response,
  /// large enough that a typical month's observations land in 1-2
  /// round-trips.
  static const int _kPageSize = 500;

  /// Skip the pull entirely if the last successful one was within
  /// this window. Prevents redundant pulls when the user signs out
  /// and back in quickly, or when the bootstrap fires multiple
  /// times during auth churn. Doesn't apply to [pullObservations]
  /// invocations with `force: true` (the explicit "Sync now"
  /// button bypasses).
  static const Duration _kPullDebounce = Duration(seconds: 30);

  /// Sentinel for the "haven't pulled before" case. Postgres'
  /// `updated_at > '1970-01-01'` filter matches every row, which
  /// is exactly what a first-launch pull wants.
  static final DateTime _kEpoch = DateTime.utc(1970);

  /// Cloud-side table name for the watermark row. Stable string
  /// — changing it would orphan every existing sync_state row.
  static const String _kObservationsTable = 'observations';

  /// Lazy Supabase client read so the service is constructible in
  /// test environments where `Supabase.initialize` hasn't run.
  /// Returns null when Supabase isn't initialized — every push
  /// then short-circuits, treating "no cloud available" the same
  /// as "not signed in."
  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  /// Pushes the row identified by [observationId] plus all its
  /// cascade rows (children, attachments, domain tags). Reads the
  /// current state from local Drift and upserts to cloud — never
  /// blocks the caller, never throws upstream. Errors are logged
  /// via debugPrint.
  ///
  /// Callers fire this from inside `unawaited(...)` so a failed
  /// push doesn't surface as a rejected Future on the local-write
  /// path.
  Future<void> pushObservation(String observationId) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;
    try {
      final row = await (_db.select(_db.observations)
            ..where((o) => o.id.equals(observationId)))
          .getSingleOrNull();
      if (row == null) return;
      // No program_id => this row predates the bootstrap or sneaked
      // in before stamping shipped. Skip — RLS on cloud requires
      // a program for membership lookup.
      if (row.programId == null) return;

      // Pull cascades up front so the whole batch happens in a
      // tight window. Reads are off the local Drift connection;
      // SQLite's connection-per-isolate model means there's no
      // contention with concurrent writes.
      final children = await (_db.select(_db.observationChildren)
            ..where((c) => c.observationId.equals(observationId)))
          .get();
      final domainTags = await (_db.select(_db.observationDomainTags)
            ..where((t) => t.observationId.equals(observationId)))
          .get();
      final attachments = await (_db.select(_db.observationAttachments)
            ..where((a) => a.observationId.equals(observationId)))
          .get();

      // Parent first — cloud RLS / FKs need it before cascade
      // rows reference it. Upsert by id so a re-push (after a
      // local edit) updates rather than 23505-conflicting.
      await client.from('observations').upsert(
            _serializeObservation(row),
          );

      // Replace cascade rows wholesale — easier than diffing.
      // Delete-then-upsert is fine within one observation's tiny
      // cascade footprint (typically <10 rows total). Operations
      // are linear in the cascade size, not the database size.
      await client
          .from('observation_children')
          .delete()
          .eq('observation_id', observationId);
      if (children.isNotEmpty) {
        await client.from('observation_children').upsert([
          for (final c in children) _serializeChild(c),
        ]);
      }

      await client
          .from('observation_domain_tags')
          .delete()
          .eq('observation_id', observationId);
      if (domainTags.isNotEmpty) {
        await client.from('observation_domain_tags').upsert([
          for (final t in domainTags) _serializeDomainTag(t),
        ]);
      }

      await client
          .from('observation_attachments')
          .delete()
          .eq('observation_id', observationId);
      if (attachments.isNotEmpty) {
        await client.from('observation_attachments').upsert([
          for (final a in attachments) _serializeAttachment(a),
        ]);
      }
    } on Object catch (e, st) {
      debugPrint('Observations push failed for $observationId: $e\n$st');
    }
  }

  /// Marks a cloud observation as deleted (UPDATE deleted_at) so
  /// other devices learn about the delete on next pull. The local
  /// row was already hard-deleted by the repository; this catches
  /// the cloud up.
  ///
  /// Caller passes [programId] explicitly because the local row is
  /// already gone by the time this runs, so we can't read it back
  /// from Drift to discover the program. Usually the repository
  /// snapshot taken before delete supplies this.
  Future<void> pushDelete({
    required String observationId,
    required String programId,
  }) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;
    try {
      await client
          .from('observations')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', observationId)
          .eq('program_id', programId);
    } on Object catch (e, st) {
      debugPrint(
        'Observations soft-delete push failed for $observationId: $e\n$st',
      );
    }
  }

  // -- Serializers ---------------------------------------------------
  //
  // Each one maps a Drift row class to the JSON shape Supabase's
  // upsert expects. Column names match the cloud schema (which
  // matches Drift's snake_case generated names). Date columns go
  // out as ISO-8601 UTC.

  Map<String, dynamic> _serializeObservation(Observation r) {
    return <String, dynamic>{
      'id': r.id,
      'target_kind': r.targetKind,
      'child_id': r.childId,
      'group_id': r.groupId,
      'activity_label': r.activityLabel,
      'domain': r.domain,
      'sentiment': r.sentiment,
      'note': r.note,
      'note_original': r.noteOriginal,
      'trip_id': r.tripId,
      'author_name': r.authorName,
      'schedule_source_kind': r.scheduleSourceKind,
      'schedule_source_id': r.scheduleSourceId,
      'activity_date': r.activityDate?.toUtc().toIso8601String(),
      'room_id': r.roomId,
      'program_id': r.programId,
      'created_at': r.createdAt.toUtc().toIso8601String(),
      'updated_at': r.updatedAt.toUtc().toIso8601String(),
      // deleted_at intentionally omitted — only pushDelete sets it.
    };
  }

  Map<String, dynamic> _serializeChild(ObservationChildrenData r) {
    return <String, dynamic>{
      'observation_id': r.observationId,
      'child_id': r.childId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _serializeDomainTag(ObservationDomainTag r) {
    return <String, dynamic>{
      'observation_id': r.observationId,
      'domain': r.domain,
    };
  }

  Map<String, dynamic> _serializeAttachment(ObservationAttachment r) {
    return <String, dynamic>{
      'id': r.id,
      'observation_id': r.observationId,
      'kind': r.kind,
      'local_path': r.localPath,
      'duration_ms': r.durationMs,
      'created_at': r.createdAt.toUtc().toIso8601String(),
    };
  }

  // -- Pull --------------------------------------------------------

  /// Watermarked incremental pull of observations + cascades for
  /// [programId]. Reads the current `last_pulled_at` from
  /// `sync_state`, queries Supabase for rows whose `updated_at` is
  /// strictly greater, upserts them into Drift, and advances the
  /// watermark.
  ///
  /// Bandwidth cost = bytes of rows changed since last pull only.
  /// First call on a fresh device ships everything once
  /// (watermark = epoch); subsequent calls ship near-zero on a
  /// quiet day.
  ///
  /// Returns the number of observation rows applied. Cascade rows
  /// are not separately counted because they ride along with their
  /// parent.
  ///
  /// Throws on transport / RLS failures; the caller (typically
  /// the auth bootstrap or a "Sync now" button) is responsible for
  /// surfacing or swallowing.
  ///
  /// Set [force] to `true` to bypass the [_kPullDebounce] window —
  /// used by the manual "Sync now" button so a teacher who just
  /// launched isn't told to wait 30 seconds for a refresh.
  Future<int> pullObservations({
    required String programId,
    bool force = false,
  }) async {
    final client = _client;
    if (client == null) return 0;
    if (client.auth.currentSession == null) return 0;

    final watermarkRow = await (_db.select(_db.syncState)
          ..where((s) =>
              s.programId.equals(programId) &
              s.targetTable.equals(_kObservationsTable)))
        .getSingleOrNull();
    final watermark = watermarkRow?.lastPulledAt ?? _kEpoch;

    if (!force && watermarkRow != null) {
      final since = DateTime.now().difference(watermarkRow.updatedAt);
      if (since < _kPullDebounce) {
        return 0;
      }
    }

    var totalApplied = 0;
    var cursor = watermark;
    // Page loop: keep fetching until a page comes back smaller
    // than the cap. Cursor advances by the highest updated_at
    // seen so we never re-fetch the same row.
    while (true) {
      final page = await client
          .from(_kObservationsTable)
          .select()
          .eq('program_id', programId)
          .gt('updated_at', cursor.toIso8601String())
          .order('updated_at')
          .limit(_kPageSize);

      if (page.isEmpty) break;
      final pageList = (page as List).cast<Map<String, dynamic>>();

      // Apply rows. Soft-deleted ones become local hard deletes
      // (their cascade rows go too via the FK cascades on Drift's
      // own schema).
      final ids = <String>[];
      final liveRows = <Map<String, dynamic>>[];
      final deletedIds = <String>[];
      for (final row in pageList) {
        final id = row['id'] as String;
        ids.add(id);
        if (row['deleted_at'] != null) {
          deletedIds.add(id);
        } else {
          liveRows.add(row);
        }
      }

      await _db.transaction(() async {
        if (deletedIds.isNotEmpty) {
          await (_db.delete(_db.observations)
                ..where((o) => o.id.isIn(deletedIds)))
              .go();
        }
        for (final row in liveRows) {
          await _db
              .into(_db.observations)
              .insertOnConflictUpdate(_deserializeObservation(row));
        }
        if (liveRows.isNotEmpty) {
          await _replaceCascades(client, liveRows.map((r) => r['id'] as String).toList());
        }
      });

      totalApplied += pageList.length;
      // Advance the cursor to the latest updated_at seen on this
      // page. Postgres returned them ordered ascending so the
      // last one is the maximum.
      final lastTs = DateTime.parse(
        pageList.last['updated_at'] as String,
      ).toUtc();
      cursor = lastTs;

      if (pageList.length < _kPageSize) break;
    }

    // Stamp the watermark — succeeds even when nothing changed,
    // so the debounce window is honored next call.
    await _db.into(_db.syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(
            programId: programId,
            targetTable: _kObservationsTable,
            lastPulledAt: cursor,
            updatedAt: Value(DateTime.now()),
          ),
        );

    return totalApplied;
  }

  /// Replaces the cascade rows for [observationIds] with whatever
  /// the cloud currently has. One round-trip per cascade table —
  /// they're not page-bounded because cascade rows are tiny (a
  /// few per parent observation typically). The whole batch fits
  /// in a single response well under the page-size threshold.
  Future<void> _replaceCascades(
    SupabaseClient client,
    List<String> observationIds,
  ) async {
    if (observationIds.isEmpty) return;

    // Wipe existing cascade rows for these parents — the cloud is
    // the source of truth post-pull.
    await (_db.delete(_db.observationChildren)
          ..where((c) => c.observationId.isIn(observationIds)))
        .go();
    await (_db.delete(_db.observationDomainTags)
          ..where((t) => t.observationId.isIn(observationIds)))
        .go();
    await (_db.delete(_db.observationAttachments)
          ..where((a) => a.observationId.isIn(observationIds)))
        .go();

    // Pull cascade rows in bulk. `inFilter` keeps it one round-
    // trip per cascade table for the entire page.
    final children = List<Map<String, dynamic>>.from(
      await client
          .from('observation_children')
          .select()
          .inFilter('observation_id', observationIds),
    );
    final domainTags = List<Map<String, dynamic>>.from(
      await client
          .from('observation_domain_tags')
          .select()
          .inFilter('observation_id', observationIds),
    );
    final attachments = List<Map<String, dynamic>>.from(
      await client
          .from('observation_attachments')
          .select()
          .inFilter('observation_id', observationIds),
    );

    for (final row in children) {
      await _db.into(_db.observationChildren).insertOnConflictUpdate(
            ObservationChildrenCompanion.insert(
              observationId: row['observation_id'] as String,
              childId: row['child_id'] as String,
            ),
          );
    }
    for (final row in domainTags) {
      await _db.into(_db.observationDomainTags).insertOnConflictUpdate(
            ObservationDomainTagsCompanion.insert(
              observationId: row['observation_id'] as String,
              domain: row['domain'] as String,
            ),
          );
    }
    for (final row in attachments) {
      await _db.into(_db.observationAttachments).insertOnConflictUpdate(
            ObservationAttachmentsCompanion.insert(
              id: row['id'] as String,
              observationId: row['observation_id'] as String,
              kind: row['kind'] as String,
              localPath: row['local_path'] as String,
              durationMs: Value(row['duration_ms'] as int?),
            ),
          );
    }
  }

  // -- Deserializer ---------------------------------------------

  /// Converts a cloud `observations` row into a Drift Companion
  /// suitable for insertOnConflictUpdate. Mirrors the serializer's
  /// shape inversely.
  ObservationsCompanion _deserializeObservation(Map<String, dynamic> r) {
    return ObservationsCompanion(
      id: Value(r['id'] as String),
      targetKind: Value(r['target_kind'] as String),
      childId: Value(r['child_id'] as String?),
      groupId: Value(r['group_id'] as String?),
      activityLabel: Value(r['activity_label'] as String?),
      domain: Value(r['domain'] as String),
      sentiment: Value(r['sentiment'] as String),
      note: Value(r['note'] as String),
      noteOriginal: Value(r['note_original'] as String?),
      tripId: Value(r['trip_id'] as String?),
      authorName: Value(r['author_name'] as String?),
      scheduleSourceKind: Value(r['schedule_source_kind'] as String?),
      scheduleSourceId: Value(r['schedule_source_id'] as String?),
      activityDate: Value(r['activity_date'] != null
          ? DateTime.parse(r['activity_date'] as String).toUtc()
          : null),
      roomId: Value(r['room_id'] as String?),
      programId: Value(r['program_id'] as String?),
      createdAt:
          Value(DateTime.parse(r['created_at'] as String).toUtc()),
      updatedAt:
          Value(DateTime.parse(r['updated_at'] as String).toUtc()),
    );
  }
}

final observationsSyncServiceProvider =
    Provider<ObservationsSyncService>((ref) {
  return ObservationsSyncService(ref.read(databaseProvider));
});
