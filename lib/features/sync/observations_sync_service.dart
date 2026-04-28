import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push-side sync for the Observations table and its cascade rows.
///
/// Slice C v1 — every local write to ObservationsRepository fires a
/// best-effort push to Supabase Postgres. The push is fire-and-
/// forget from the local-write's perspective: if it fails (network
/// down, RLS rejection, schema drift), the local mutation already
/// succeeded and the next push attempt re-tries by re-reading the
/// row's current state.
///
/// Pull-side (deltas-on-sign-in) lives in a separate slice. This
/// service only ships the push half: writes go up, but reads are
/// still local-only until the pull lands.
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
}

final observationsSyncServiceProvider =
    Provider<ObservationsSyncService>((ref) {
  return ObservationsSyncService(ref.read(databaseProvider));
});
