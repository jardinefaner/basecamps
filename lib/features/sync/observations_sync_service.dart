import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push + pull sync for the Observations table and its cascade rows.
///
/// Push is now delegated to [SyncEngine] via [observationsSpec] —
/// every mutation in `ObservationsRepository` still calls
/// [pushObservation] / [pushDelete] here, but those methods just
/// forward to the generic engine. The legacy per-table serializers
/// are gone: the engine reads rows from Drift's table-name-keyed
/// metadata and ships them through.
///
/// Pull stays bespoke for now — we may consolidate later. It's
/// watermarked, paged, and debounced like the engine's pull, but it
/// hand-deserializes observation rows back into typed Companions
/// because callers (the auth bootstrap) still rely on the typed
/// return shape.
class ObservationsSyncService {
  ObservationsSyncService(this._db, this._engine);

  final AppDatabase _db;
  final SyncEngine _engine;

  /// Cap rows fetched per round-trip. See sync_engine.dart for the
  /// math behind the 500 row sweet spot.
  static const int _kPageSize = 500;

  /// Skip the pull entirely if the last successful one was within
  /// this window. Bypassed by `force: true` (manual "Sync now").
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
  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  /// Pushes the row identified by [observationId] plus all its
  /// cascade rows. Delegates to the generic engine — kept here as
  /// a thin wrapper so existing callers don't need rewriting.
  Future<void> pushObservation(String observationId) {
    return _engine.pushRow(observationsSpec, observationId);
  }

  /// Marks a cloud observation as deleted. Delegates to the engine —
  /// the engine handles the soft-delete UPDATE and program scoping.
  Future<void> pushDelete({
    required String observationId,
    required String programId,
  }) {
    return _engine.pushDelete(
      spec: observationsSpec,
      id: observationId,
      programId: programId,
    );
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
  /// Set [force] to `true` to bypass the [_kPullDebounce] window.
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
  /// suitable for insertOnConflictUpdate.
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

  // Suppress unused-field analyzer warning on debugPrint import path
  // when this file is trimmed further. Kept for consistency with the
  // rest of the codebase's logging style.
  // ignore: unused_element
  static void _logUnused() => debugPrint('');
}

final observationsSyncServiceProvider =
    Provider<ObservationsSyncService>((ref) {
  return ObservationsSyncService(
    ref.read(databaseProvider),
    ref.read(syncEngineProvider),
  );
});
