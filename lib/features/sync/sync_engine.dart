import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Declarative spec for a single program-scoped table's sync.
///
/// One spec per table. Each describes:
///  - the SQL table name (same locally and in cloud — we keep them
///    aligned by convention)
///  - any cascade tables that ride with the parent
///  - what columns of the parent are date-typed (need ISO string
///    conversion on push, parsing on pull)
///
/// Adding a new synced table is one spec — the [SyncEngine] does
/// the rest. No per-table push/pull/serialize code.
@immutable
class TableSpec {
  const TableSpec({
    required this.table,
    required this.dateColumns,
    this.cascades = const [],
  });

  /// SQL table name, e.g. `observations`. Used both locally
  /// (Drift's snake_case generated names) and in cloud (matching
  /// migration). Same name on both sides — anything else is a
  /// future-headache magnet.
  final String table;

  /// Column names whose values are DateTime locally (Drift stores
  /// as int unix-seconds) and timestamptz in cloud (expects ISO
  /// strings). The engine reads these from rows on push and
  /// converts; on pull it parses incoming ISO strings to ints.
  ///
  /// Always include 'created_at' and 'updated_at'. Add any other
  /// `dateTime()` columns from the Drift table.
  final Set<String> dateColumns;

  /// Cascade tables — rows that belong to this parent and should
  /// follow it through sync. Replaced wholesale on push (cloud
  /// state matches what local has), wiped+re-applied on pull.
  final List<CascadeSpec> cascades;
}

/// Cascade table spec. The engine knows how to filter local rows
/// (`WHERE parentColumn IN (parentIds)`) and apply them through
/// cloud equivalently.
@immutable
class CascadeSpec {
  const CascadeSpec({
    required this.table,
    required this.parentColumn,
    this.dateColumns = const {},
  });

  final String table;

  /// SQL column on the cascade table that points at the parent.
  /// e.g. for `observation_children`, parentColumn is
  /// `observation_id`.
  final String parentColumn;

  /// Same role as [TableSpec.dateColumns] for the cascade table.
  /// Most cascades only have `created_at` (or nothing).
  final Set<String> dateColumns;
}

/// Generic sync engine. Pushes/pulls program-scoped rows and their
/// cascades through Supabase Postgres. Map-based — every row is
/// marshalled as `Map<String, Object?>` end-to-end so we don't
/// duplicate per-table typed serializers.
///
/// Single source of truth for sync behavior:
///   - pull: watermarked, page-capped (500/round-trip), debounced
///     (30s window), uses (program_id, updated_at) cloud index
///   - push: fire-and-forget; reads current row state from local,
///     upserts parent, replaces cascades wholesale
///   - delete: soft on cloud (UPDATE deleted_at), hard locally
///   - cost shape: deltas-only on quiet days, ~bytes-changed-since-
///     last-pull bandwidth
class SyncEngine {
  SyncEngine(this._db);

  final AppDatabase _db;

  /// Cap rows fetched per pull round-trip. See observations_sync_
  /// service.dart's _kPageSize comment for the math.
  static const int _kPageSize = 500;

  /// Skip pull if the last successful one was within this window.
  /// Bypassed by `force: true` (manual "Sync now").
  static const Duration _kPullDebounce = Duration(seconds: 30);

  /// Coalesce window for repeated push of the same row. Rapid
  /// edits to the same observation (typing, formatting,
  /// bulk-toggling kids) collapse into a single cloud upsert
  /// after the user pauses for this long. Saves bandwidth and
  /// upstream churn at the cost of a tiny visible-on-cloud lag.
  /// 250ms is fast enough that a normal Save → cross-device
  /// pull arrives within "feels instant," slow enough to
  /// coalesce keystroke-driven flurries.
  static const Duration _kPushDebounce = Duration(milliseconds: 250);

  /// Sentinel watermark for first-launch pull (everything > epoch).
  static final DateTime _kEpoch = DateTime.utc(1970);

  /// Pending-push timers keyed by `${table}/${id}`. When a new
  /// pushRow comes in, we cancel the existing timer for that key
  /// and start a fresh one — last write within the debounce window
  /// wins, all earlier ones collapse into the eventual fire.
  ///
  /// Only one push per key is ever in flight at once.
  final Map<String, Timer> _pendingPushes = <String, Timer>{};

  /// Per-(table, parentId) cache of the last cascade-payload
  /// fingerprint we successfully pushed. Used by [pushRow] to
  /// skip the cascade delete + insert pair when the local cascade
  /// rows haven't changed since the last push.
  ///
  /// Saves 2 round-trips per cascade table per parent push when
  /// the parent is being re-pushed for an unrelated reason
  /// (e.g., editing an observation's note doesn't change which
  /// children it tags). Memory-only — empties on app restart,
  /// which is fine because a fresh launch's first push pays the
  /// full cost once and caches from there.
  final Map<String, String> _lastCascadeFingerprint = <String, String>{};

  /// Active realtime channel for the current program. Single channel
  /// multiplexes change events for every spec — cheaper than one
  /// channel per table (each open channel is a heartbeat-burning
  /// presence on the WS). Null when not subscribed (signed out, or
  /// pre-subscribe).
  RealtimeChannel? _realtimeChannel;
  String? _realtimeProgramId;

  /// Stream of push failures. Emits each time a debounced push hits
  /// an exception (network, RLS rejection, validation). The app
  /// listens at the root and surfaces a snackbar so users see when
  /// something they thought saved didn't actually reach the cloud
  /// — without this, push errors only landed in `debugPrint` and
  /// gave the false impression of "live sync working" when really
  /// every write was 403-ing silently.
  Stream<SyncPushError> get pushErrors => _pushErrorController.stream;
  final StreamController<SyncPushError> _pushErrorController =
      StreamController<SyncPushError>.broadcast();

  /// Realtime liveness signal. Emits a fresh [RealtimeStatus] each
  /// time the realtime layer's state changes:
  ///   * subscribe — channel opened ("subscribed" tone in the UI).
  ///   * unsubscribe — channel torn down ("offline" tone).
  ///   * each applied realtime change — bumps `lastEventAt` so the
  ///     UI's "Live · 3s ago" indicator ticks fresh.
  ///
  /// Broadcast so multiple widgets can subscribe (the program-
  /// detail screen, the today screen, etc.).
  Stream<RealtimeStatus> get realtimeStatus =>
      _realtimeStatusController.stream;
  final StreamController<RealtimeStatus> _realtimeStatusController =
      StreamController<RealtimeStatus>.broadcast();

  /// Latest snapshot. Late-subscribers can read this synchronously
  /// without waiting for the next event.
  RealtimeStatus _currentStatus = const RealtimeStatus(
    isSubscribed: false,
    programId: null,
    lastEventAt: null,
  );
  RealtimeStatus get currentRealtimeStatus => _currentStatus;

  void _emitRealtimeStatus(RealtimeStatus next) {
    _currentStatus = next;
    if (!_realtimeStatusController.isClosed) {
      _realtimeStatusController.add(next);
    }
  }

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  // -- Push --------------------------------------------------------

  /// Pushes the row identified by [id] in [spec] plus all its
  /// cascade rows. Coalesced — repeated calls for the same
  /// (table, id) within [_kPushDebounce] collapse into a single
  /// upsert after the user pauses. Best-effort: catches its own
  /// errors and logs via debugPrint so a failed push doesn't
  /// bubble up to the local-write callsite.
  ///
  /// Returns immediately. The actual push fires after the
  /// debounce window. Caveat: if the app is killed during that
  /// 250ms window, the most recent edit doesn't reach cloud
  /// until the next mutation re-triggers a push (any later
  /// pushRow on the same row will read the latest state from
  /// Drift, so no data loss — just a sync lag).
  Future<void> pushRow(TableSpec spec, String id) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;

    final key = '${spec.table}/$id';
    _pendingPushes[key]?.cancel();
    _pendingPushes[key] = Timer(_kPushDebounce, () {
      _pendingPushes.remove(key);
      // The actual push runs detached so the timer callback
      // returns instantly. Errors are caught inside _pushRowNow.
      unawaited(_pushRowNow(spec, id));
    });
  }

  /// The actual push body, separated from the debouncer.
  Future<void> _pushRowNow(TableSpec spec, String id) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;

    try {
      final row = await _readLocalRow(spec.table, id);
      if (row == null) return;
      // Without a program_id the cloud RLS check would always
      // reject — same row will get retried on the next mutation
      // once the bootstrap-backfill stamps it.
      if (row['program_id'] == null) return;

      // Field-level dirty tracking is the only push model now.
      //
      //   * Non-empty dirty_fields → partial UPDATE for existing
      //     cloud rows, full upsert when cloud doesn't have the
      //     row yet (the new-row case is what _pushPartialUpdate
      //     internally falls through to).
      //   * Empty dirty_fields → no field-level edits to send.
      //     This is either an insert path that hasn't yet stamped
      //     dirty_fields (rare; addX repo methods don't markDirty
      //     on insert because the row's first push is a full
      //     upsert) OR a debounced push that already fired.
      //     Either way: send a full upsert if cloud is missing
      //     the row, otherwise no-op.
      final dirtyFields = await _db.readDirtyFields(spec.table, id);
      if (dirtyFields.isNotEmpty) {
        await _pushPartialUpdate(client, spec, id, row, dirtyFields);
        await _pushCascades(client, spec, id);
        return;
      }

      // Insert path: cloud has no row for this id. Push the full
      // row. (Updates always go through the dirty-fields branch
      // above; if we land here on an existing cloud row, the
      // earlier push already cleared dirty_fields and there's
      // nothing new to send.)
      final cloudUpdatedAt = await _readCloudUpdatedAt(
        client,
        spec.table,
        id,
      );
      if (cloudUpdatedAt == null) {
        await client.from(spec.table).upsert(
              _toCloudShape(row, spec.dateColumns),
            );
        await _pushCascades(client, spec, id);
      } else {
        // Cloud already has this row, no dirty fields locally —
        // nothing to push. Cascades may still need to flush if
        // the parent's child rows changed; the fingerprint check
        // inside _pushCascades short-circuits when they haven't.
        await _pushCascades(client, spec, id);
      }
    } on Object catch (e, st) {
      debugPrint('Sync push failed for ${spec.table}/$id: $e\n$st');
      // Broadcast to listeners (the app shell shows a snackbar).
      // Don't rethrow — push runs detached from any user gesture,
      // and we'd just log-and-swallow at every call site anyway.
      if (!_pushErrorController.isClosed) {
        _pushErrorController.add(SyncPushError(
          table: spec.table,
          id: id,
          error: e,
        ));
      }
    }
  }

  /// Phase 2: partial UPDATE via dirty_fields. Sends only the
  /// fields the user actually edited locally (plus id, updated_at,
  /// program_id) to cloud as an UPDATE — concurrent edits on
  /// different fields no longer overwrite each other because each
  /// device's UPDATE only touches its own changed columns.
  ///
  /// If the cloud doesn't have the row yet (fresh insert that's
  /// never been pushed), falls through to a full upsert. Otherwise,
  /// constructs a payload of `{id, updated_at, program_id, ...dirty}`
  /// and sends `update().eq('id', id)`.
  ///
  /// On success, clears the dirty_fields list so subsequent
  /// no-op pushes (debounce re-fires, etc.) don't re-send the
  /// same partial update.
  Future<void> _pushPartialUpdate(
    SupabaseClient client,
    TableSpec spec,
    String id,
    Map<String, Object?> row,
    List<String> dirtyFields,
  ) async {
    // Cloud-row existence check. If the cloud doesn't have this
    // id, our partial UPDATE would match zero rows and the local
    // edit would never reach cloud. Detect via a HEAD-style
    // SELECT on id; if missing, do a full upsert instead.
    final cloudExists = await _readCloudUpdatedAt(
      client,
      spec.table,
      id,
    );
    if (cloudExists == null) {
      // No row in cloud — full upsert (insert path).
      await client.from(spec.table).upsert(
            _toCloudShape(row, spec.dateColumns),
          );
      await _db.clearDirtyFields(spec.table, id);
      return;
    }
    // Cloud has the row; partial UPDATE.
    final shaped = _toCloudShape(row, spec.dateColumns);
    final payload = <String, Object?>{
      // Always include the row's identity + cloud-side housekeeping
      // fields. updated_at lets cloud's last-write-wins logic + our
      // pull freshness tracking advance. program_id is required by
      // RLS for some tables (idempotent here — it doesn't change
      // post-creation).
      if (shaped.containsKey('updated_at'))
        'updated_at': shaped['updated_at'],
      if (shaped.containsKey('program_id'))
        'program_id': shaped['program_id'],
      // The actually-dirty fields the user edited.
      for (final field in dirtyFields)
        if (shaped.containsKey(field)) field: shaped[field],
    };
    await client
        .from(spec.table)
        .update(payload)
        .eq('id', id);
    await _db.clearDirtyFields(spec.table, id);
  }

  /// Push the cascade rows (parent_children, attendance, etc.)
  /// for a parent row. Called both by the legacy full-upsert path
  /// and the new partial-UPDATE path — partial updates only
  /// modify dirty parent fields, but the user might have also
  /// added / removed cascade rows (a child's parents list, for
  /// example). The fingerprint cache short-circuits when the
  /// cascade payload hasn't changed, and the cold-start guard
  /// from commit 7ae87cc protects against wholesale-DELETEing
  /// cloud's cascades on a device that never pulled them.
  Future<void> _pushCascades(
    SupabaseClient client,
    TableSpec spec,
    String id,
  ) async {
    for (final cascade in spec.cascades) {
      final cascadeRows = await _readCascadeRows(
        cascade.table,
        cascade.parentColumn,
        id,
      );

      final fingerprintKey =
          '${cascade.table}/${cascade.parentColumn}/$id';
      final fingerprint = _fingerprintRows(cascadeRows);
      if (_lastCascadeFingerprint[fingerprintKey] == fingerprint) {
        // Cascade payload unchanged since our last push — skip
        // the delete+insert.
        continue;
      }

      // Cold-start safety (commit 7ae87cc): refuse to wholesale-
      // DELETE cloud's cascade rows on the very first push when
      // local has zero. Likely cause is "I never pulled the
      // cascades," not "I deliberately emptied them."
      if (_lastCascadeFingerprint[fingerprintKey] == null &&
          cascadeRows.isEmpty) {
        _lastCascadeFingerprint[fingerprintKey] = fingerprint;
        continue;
      }

      await client
          .from(cascade.table)
          .delete()
          .eq(cascade.parentColumn, id);
      if (cascadeRows.isNotEmpty) {
        await client.from(cascade.table).upsert([
          for (final r in cascadeRows)
            _toCloudShape(r, cascade.dateColumns),
        ]);
      }
      _lastCascadeFingerprint[fingerprintKey] = fingerprint;
    }
  }

  /// Sweep every entity table for rows whose `dirty_fields` is
  /// non-empty and re-fire pushRow for them. The "agent" that
  /// keeps sync invisible — when an earlier push errored (network
  /// blip, RLS race, app killed mid-debounce, etc.) the dirty
  /// flags stay set on local; this sweep picks them up and tries
  /// again. Called on app foreground, sign-in completion, and
  /// after the bootstrap pull settles.
  ///
  /// Cheap on the steady state (one indexed scan per table; zero
  /// rows on a synced device). Does not block the caller — each
  /// pushRow goes through the existing debounced path.
  Future<int> drainPendingPushes(List<TableSpec> specs) async {
    final client = _client;
    if (client == null) return 0;
    if (client.auth.currentSession == null) return 0;
    var queued = 0;
    for (final spec in specs) {
      try {
        final dirtyRows = await _db.customSelect(
          'SELECT "id" FROM "${spec.table}" '
          'WHERE "dirty_fields" IS NOT NULL '
          "AND \"dirty_fields\" != '' "
          "AND \"dirty_fields\" != '[]'",
        ).get();
        for (final row in dirtyRows) {
          final id = row.data['id'];
          if (id is String) {
            unawaited(pushRow(spec, id));
            queued++;
          }
        }
      } on Object catch (e) {
        // Likely cause: the dirty_fields column doesn't exist
        // yet on a partial-migration DB. The heal helper adds it
        // on the next launch; until then, skip this table.
        debugPrint(
          'drainPendingPushes skipped ${spec.table}: $e',
        );
      }
    }
    if (queued > 0) {
      debugPrint('drainPendingPushes queued $queued row(s).');
    }
    return queued;
  }

  /// Soft-delete on cloud. Local row is already hard-deleted by
  /// the repository.
  Future<void> pushDelete({
    required TableSpec spec,
    required String id,
    required String programId,
  }) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;
    try {
      await client
          .from(spec.table)
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id)
          .eq('program_id', programId);
    } on Object catch (e, st) {
      debugPrint('Sync delete failed for ${spec.table}/$id: $e\n$st');
    }
  }

  // -- Pull --------------------------------------------------------

  /// Watermarked, paged pull for [spec]. Returns the count of
  /// parent rows applied (cascade rows aren't separately counted
  /// — they ride along).
  Future<int> pullTable({
    required TableSpec spec,
    required String programId,
    bool force = false,
  }) async {
    final client = _client;
    if (client == null) return 0;
    if (client.auth.currentSession == null) return 0;

    final watermarkRow = await (_db.select(_db.syncState)
          ..where((s) =>
              s.programId.equals(programId) &
              s.targetTable.equals(spec.table)))
        .getSingleOrNull();
    final watermark = watermarkRow?.lastPulledAt ?? _kEpoch;

    if (!force && watermarkRow != null) {
      final since = DateTime.now().difference(watermarkRow.updatedAt);
      if (since < _kPullDebounce) return 0;
    }

    var totalApplied = 0;
    var cursor = watermark;
    while (true) {
      final page = List<Map<String, dynamic>>.from(
        await client
            .from(spec.table)
            .select()
            .eq('program_id', programId)
            .gt('updated_at', cursor.toIso8601String())
            .order('updated_at')
            .limit(_kPageSize),
      );
      if (page.isEmpty) break;

      final liveRows = <Map<String, dynamic>>[];
      final deletedIds = <String>[];
      for (final row in page) {
        if (row['deleted_at'] != null) {
          deletedIds.add(row['id'] as String);
        } else {
          liveRows.add(row);
        }
      }

      // Concurrent-edit detection. For each live remote row,
      // sample local updated_at BEFORE the upsert so we can spot
      // the case where the local was edited between the watermark
      // and now (i.e., we're about to overwrite an unsynced
      await _db.transaction(() async {
        if (deletedIds.isNotEmpty) {
          await _db.customUpdate(
            'DELETE FROM "${spec.table}" WHERE id IN (${_placeholders(deletedIds.length)})',
            variables: [for (final id in deletedIds) Variable<String>(id)],
          );
        }
        for (final row in liveRows) {
          // Phase 3: dirty-field-preserving merge. Read local's
          // dirty_fields list for this id; strip those keys from
          // the cloud payload before upserting. The "ON CONFLICT
          // DO UPDATE SET col = excluded.col" SQL only touches
          // columns it's given, so omitting dirty columns means
          // local's un-pushed edits survive the pull. New local
          // rows (no row yet → dirty_fields is null) get the full
          // cloud payload. Edge case: row exists locally but has
          // no dirty_fields → behaves identically to the old
          // wholesale upsert (cloud overwrites every column).
          final dirty = await _db.readDirtyFields(
            spec.table,
            row['id'] as String,
          );
          final payload = dirty.isEmpty
              ? row
              : <String, dynamic>{
                  for (final entry in row.entries)
                    if (!dirty.contains(entry.key))
                      entry.key: entry.value,
                };
          await _upsertLocalRow(spec.table, payload, spec.dateColumns);
        }
        if (liveRows.isNotEmpty) {
          await _replaceLocalCascades(
            client,
            spec.cascades,
            liveRows.map((r) => r['id'] as String).toList(),
          );
        }
      });

      totalApplied += page.length;
      cursor = DateTime.parse(page.last['updated_at'] as String).toUtc();
      if (page.length < _kPageSize) break;
    }

    await _db.into(_db.syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(
            programId: programId,
            targetTable: spec.table,
            lastPulledAt: cursor,
            updatedAt: Value(DateTime.now()),
          ),
        );
    return totalApplied;
  }

  // -- Realtime ----------------------------------------------------

  /// Opens a single Supabase Realtime channel that listens for
  /// changes on every entity table in [specs] (cascade tables ride
  /// along — when a parent change lands we re-fetch its cascades).
  /// Filters server-side by [programId] so the channel only
  /// receives rows the user is allowed to see anyway; RLS still
  /// gates the underlying SELECT.
  ///
  /// Echo-safe: events arriving from this device's own pushes are
  /// applied like any other, but the local upsert short-circuits
  /// when remote's `updated_at` matches what we already have. The
  /// "last write wins by updated_at" rule plus the cloud trigger
  /// that bumps updated_at on every UPDATE keeps echo loops
  /// harmless — the worst case is a redundant local re-write of
  /// the same bytes.
  ///
  /// Idempotent: calling subscribe twice for the same program is
  /// a no-op; calling it for a different program tears down the
  /// previous channel first. Caller wires this from the auth
  /// bootstrap (subscribe on sign-in, [unsubscribeFromRealtime]
  /// on sign-out).
  Future<void> subscribeToRealtime({
    required String programId,
    required List<TableSpec> specs,
    bool force = false,
  }) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;

    // Idempotency: same program + live channel handle → no-op.
    // `force: true` bypasses this so callers (the app-resume
    // recovery path) can tear down and rebuild even when the
    // engine still thinks the channel is healthy. A realtime
    // channel can be silently dead — mobile-radio sleep, browser
    // tab throttling, network change — without the engine
    // noticing, since the websocket close event isn't always
    // delivered. Forcing the rebuild costs one channel handshake
    // (~100ms); cheaper than the user wondering why edits from
    // another device aren't showing up.
    if (!force &&
        _realtimeProgramId == programId &&
        _realtimeChannel != null) {
      return;
    }
    await unsubscribeFromRealtime();

    final channel = client.channel('basecamp-realtime-$programId');

    for (final spec in specs) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: spec.table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'program_id',
          value: programId,
        ),
        callback: (payload) =>
            unawaited(_applyRealtimeChange(client, spec, payload)),
      );
    }

    channel.subscribe();
    _realtimeChannel = channel;
    _realtimeProgramId = programId;
    _emitRealtimeStatus(RealtimeStatus(
      isSubscribed: true,
      programId: programId,
      lastEventAt: _currentStatus.lastEventAt,
    ));
  }

  /// Tears down the current realtime channel. Safe to call when no
  /// channel is open. Invoked by sign-out and by every subscribe
  /// call (so a program-switch transitions cleanly).
  Future<void> unsubscribeFromRealtime() async {
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    _realtimeProgramId = null;
    if (channel == null) {
      _emitRealtimeStatus(RealtimeStatus(
        isSubscribed: false,
        programId: null,
        lastEventAt: _currentStatus.lastEventAt,
      ));
      return;
    }
    final client = _client;
    if (client == null) return;
    try {
      await client.removeChannel(channel);
    } on Object catch (e) {
      debugPrint('Realtime unsubscribe failed: $e');
    }
    _emitRealtimeStatus(RealtimeStatus(
      isSubscribed: false,
      programId: null,
      lastEventAt: _currentStatus.lastEventAt,
    ));
  }

  /// Applies a realtime payload to local Drift. Mirrors the pull
  /// path's logic — checks `updated_at` against local state, skips
  /// stale events, hard-deletes on tombstones (deleted_at), and
  /// re-fetches cascades after a parent change so the local view
  /// stays consistent.
  Future<void> _applyRealtimeChange(
    SupabaseClient client,
    TableSpec spec,
    PostgresChangePayload payload,
  ) async {
    // Tick the live indicator BEFORE the apply runs — even if
    // the apply throws (echo-skip, FK conflict, etc.), the fact
    // that we received an event is real liveness signal that
    // belongs in the UI.
    _emitRealtimeStatus(RealtimeStatus(
      isSubscribed: _currentStatus.isSubscribed,
      programId: _currentStatus.programId,
      lastEventAt: DateTime.now(),
    ));
    try {
      final eventType = payload.eventType;
      if (eventType == PostgresChangeEvent.delete) {
        // Realtime DELETEs are rare in our model (cloud uses soft
        // delete via UPDATE deleted_at), but if a row gets hard-
        // deleted out of band, mirror locally.
        final id = payload.oldRecord['id'];
        if (id is String) {
          await _db.customUpdate(
            'DELETE FROM "${spec.table}" WHERE id = ?',
            variables: [Variable<String>(id)],
          );
        }
        return;
      }

      final row = Map<String, dynamic>.from(payload.newRecord);
      final id = row['id'];
      if (id is! String) return;

      // Tombstone: cloud row is soft-deleted, mirror locally.
      if (row['deleted_at'] != null) {
        await _db.customUpdate(
          'DELETE FROM "${spec.table}" WHERE id = ?',
          variables: [Variable<String>(id)],
        );
        return;
      }

      // Echo-skip: if the local row is at-or-newer than the
      // incoming one, this is just our own push coming back to
      // us. Nothing to do.
      final remoteUpdatedAt =
          DateTime.parse(row['updated_at'] as String).toUtc();
      final localTs = await _localUpdatedAt(spec.table, id);
      if (localTs != null && !remoteUpdatedAt.isAfter(localTs)) {
        return;
      }

      // Apply parent + re-fetch cascades. One round-trip per
      // cascade table; cheap because the parent event is rare
      // relative to keystroke-rate events.
      //
      // Phase 3: dirty-field-preserving merge — strip any locally-
      // dirty columns from the realtime row so an in-flight local
      // edit (not yet pushed) isn't clobbered by an event from
      // another device.
      final dirty = await _db.readDirtyFields(spec.table, id);
      final mergedRow = dirty.isEmpty
          ? row
          : <String, dynamic>{
              for (final entry in row.entries)
                if (!dirty.contains(entry.key)) entry.key: entry.value,
            };
      await _db.transaction(() async {
        await _upsertLocalRow(spec.table, mergedRow, spec.dateColumns);
        if (spec.cascades.isNotEmpty) {
          await _replaceLocalCascades(client, spec.cascades, [id]);
        }
      });
    } on Object catch (e, st) {
      debugPrint(
        'Realtime apply failed for ${spec.table}: $e\n$st',
      );
    }
  }

  /// Read `updated_at` from the cloud row for [id] in [table].
  /// Returns null if the row doesn't exist in cloud (a brand-new
  /// local row that's never been pushed) or the read fails (RLS,
  /// network). Used by the pre-push freshness check to decide
  /// whether to overwrite the cloud row or pull instead.
  Future<DateTime?> _readCloudUpdatedAt(
    SupabaseClient client,
    String table,
    String id,
  ) async {
    try {
      final raw = await client
          .from(table)
          .select('updated_at')
          .eq('id', id)
          .maybeSingle();
      if (raw == null) return null;
      final ts = raw['updated_at'];
      if (ts is String) return DateTime.parse(ts).toUtc();
      return null;
    } on Object catch (e) {
      debugPrint('Cloud updated_at read failed for $table/$id: $e');
      return null;
    }
  }

// _readCloudRow + _additiveMerge removed in Phase 5 — they
// served the legacy full-row push path's pre-push conflict
// resolution. Field-level dirty tracking (Phase 2 / 4) made
// that path obsolete: partial UPDATEs don't conflict on
// untouched fields by definition.

  // _parseUpdatedAt removed in Phase 5 — used only by the
  // additive-merge legacy path that's now gone.

  /// Reads `updated_at` for one row (Drift returns it as int unix
  /// seconds). Returns null when the row doesn't exist locally.
  Future<DateTime?> _localUpdatedAt(String table, String id) async {
    final result = await _db.customSelect(
      'SELECT updated_at FROM "$table" WHERE id = ?',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();
    if (result == null) return null;
    final ts = result.data['updated_at'];
    if (ts is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
  }

  // -- Internals ---------------------------------------------------

  /// Reads a local row as a column-name → value map. Drift's
  /// customSelect returns DateTime columns as `int` (unix
  /// seconds). The engine converts both directions.
  Future<Map<String, Object?>?> _readLocalRow(
    String table,
    String id,
  ) async {
    final result = await _db.customSelect(
      'SELECT * FROM "$table" WHERE id = ?',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();
    return result?.data;
  }

  Future<List<Map<String, Object?>>> _readCascadeRows(
    String table,
    String parentColumn,
    String parentId,
  ) async {
    final results = await _db.customSelect(
      'SELECT * FROM "$table" WHERE "$parentColumn" = ?',
      variables: [Variable<String>(parentId)],
    ).get();
    return [for (final r in results) r.data];
  }

  /// Columns the engine never reads from cloud or writes to cloud
  /// — each device owns them locally. Filtered out of both push
  /// payloads (`_toCloudShape`) and pull projections
  /// (`_upsertLocalRow`) so a device never imports another
  /// device's local-only column value over its own.
  ///
  ///   * `deleted_at` — cloud-only soft-delete tombstone; local
  ///     hard-deletes the row, so cloud's deleted_at never has a
  ///     local mirror.
  ///   * `dirty_fields` — local-only sync state, see Phase 1.
  ///   * `avatar_path` — local filesystem handle, only valid on
  ///     the device that captured the photo. The cross-device
  ///     handle is `avatar_storage_path` (the Supabase Storage
  ///     key). Pre-fix the cloud row carried this useless string,
  ///     polluting other devices' rendering.
  ///   * `local_path` (on `observation_attachments`) — same shape
  ///     as `avatar_path` for attachments.
  ///   * `remote_url`, `thumbnail_path` (on
  ///     `observation_attachments`) — dead pre-Storage placeholders
  ///     in the local Drift schema. Cloud doesn't have either
  ///     column, so a push that included them blew up with
  ///     `PGRST204: Could not find the 'remote_url' column …`
  ///     and the whole observation cascade silently failed —
  ///     attachments never reached cloud. Filtering them on push
  ///     unwedges the cascade. (We could also drop the columns
  ///     from local Drift, but that's a separate cleanup; this
  ///     fix is one line and zero migrations.)
  static const _kLocalOnlyColumns = <String>{
    'deleted_at',
    'dirty_fields',
    'avatar_path',
    'local_path',
    'remote_url',
    'thumbnail_path',
  };

  /// Drift returns `int` for DateTime-typed columns (unix-seconds
  /// since drift's encoder). Postgres expects ISO strings. Convert
  /// every column the spec marked as date-typed.
  Map<String, Object?> _toCloudShape(
    Map<String, Object?> row,
    Set<String> dateColumns,
  ) {
    return <String, Object?>{
      for (final entry in row.entries)
        // Local-only columns never make it onto the wire — invert
        // the membership check so the collection-literal stays a
        // simple if/else without `continue` (which Dart doesn't
        // allow inside a collection literal).
        if (!_kLocalOnlyColumns.contains(entry.key))
          if (dateColumns.contains(entry.key) && entry.value != null)
            entry.key: DateTime.fromMillisecondsSinceEpoch(
              (entry.value! as int) * 1000,
              isUtc: true,
            ).toIso8601String()
          else
            entry.key: entry.value,
    };
  }

  /// Upserts a cloud row into local Drift via raw SQL. Date
  /// columns flip back from ISO string to unix seconds (Drift's
  /// on-disk encoding). Bool columns from Postgres come as `true`
  /// or `false`; SQLite stores 1/0 — Drift's customInsert binding
  /// handles that automatically.
  Future<void> _upsertLocalRow(
    String table,
    Map<String, dynamic> row,
    Set<String> dateColumns,
  ) async {
    // Filter out local-only columns when projecting cloud → local.
    // `deleted_at` is cloud-only (we hard-delete locally). The
    // per-device columns (`avatar_path`, `local_path`,
    // `dirty_fields`) belong to whichever device is reading the
    // pull, NOT the device that pushed the row. Importing them
    // would clobber this device's own state.
    final projected = <String, Object?>{};
    for (final entry in row.entries) {
      if (_kLocalOnlyColumns.contains(entry.key)) continue;
      if (dateColumns.contains(entry.key) && entry.value != null) {
        projected[entry.key] =
            DateTime.parse(entry.value as String).millisecondsSinceEpoch ~/
                1000;
      } else {
        projected[entry.key] = entry.value;
      }
    }
    final cols = projected.keys.toList();
    final colList = cols.map((c) => '"$c"').join(', ');
    final placeholders = _placeholders(cols.length);
    final updates = cols
        .where((c) => c != 'id')
        .map((c) => '"$c" = excluded."$c"')
        .join(', ');
    await _db.customInsert(
      'INSERT INTO "$table" ($colList) VALUES ($placeholders) '
      'ON CONFLICT(id) DO UPDATE SET $updates',
      variables: [
        for (final c in cols) _toVariable(projected[c]),
      ],
    );
  }

  Future<void> _replaceLocalCascades(
    SupabaseClient client,
    List<CascadeSpec> cascades,
    List<String> parentIds,
  ) async {
    if (parentIds.isEmpty || cascades.isEmpty) return;
    for (final cascade in cascades) {
      // Wipe locally — cloud is the source of truth for this pull.
      await _db.customUpdate(
        'DELETE FROM "${cascade.table}" '
        'WHERE "${cascade.parentColumn}" IN (${_placeholders(parentIds.length)})',
        variables: [for (final id in parentIds) Variable<String>(id)],
      );

      // Pull cascade rows in bulk. inFilter keeps it one round-trip
      // for the entire page's parents, regardless of how many.
      final cloudRows = List<Map<String, dynamic>>.from(
        await client
            .from(cascade.table)
            .select()
            .inFilter(cascade.parentColumn, parentIds),
      );
      for (final row in cloudRows) {
        await _upsertLocalCascadeRow(
          cascade.table,
          row,
          cascade.dateColumns,
        );
      }
    }
  }

  /// Cascade tables don't all have `id` as PK — many use composite
  /// keys (e.g. observation_children PK = (observation_id,
  /// child_id)). Use plain INSERT OR REPLACE so the upsert works
  /// without needing per-table conflict targets.
  Future<void> _upsertLocalCascadeRow(
    String table,
    Map<String, dynamic> row,
    Set<String> dateColumns,
  ) async {
    final projected = <String, Object?>{};
    for (final entry in row.entries) {
      if (dateColumns.contains(entry.key) && entry.value != null) {
        projected[entry.key] =
            DateTime.parse(entry.value as String).millisecondsSinceEpoch ~/
                1000;
      } else {
        projected[entry.key] = entry.value;
      }
    }
    final cols = projected.keys.toList();
    final colList = cols.map((c) => '"$c"').join(', ');
    final placeholders = _placeholders(cols.length);
    await _db.customInsert(
      'INSERT OR REPLACE INTO "$table" ($colList) VALUES ($placeholders)',
      variables: [
        for (final c in cols) _toVariable(projected[c]),
      ],
    );
  }

  /// Stable string fingerprint for a list of cascade rows. The
  /// goal isn't cryptographic — just "same input always yields
  /// same string" so we can compare against the last-push value.
  /// Sorts row keys to normalize Dart's Map iteration order, then
  /// joins fields. Null bytes in values would only appear in
  /// notes-style text columns; the unique separator avoids
  /// collisions between (a='12', b='3') and (a='1', b='23').
  static String _fingerprintRows(List<Map<String, Object?>> rows) {
    final buf = StringBuffer();
    for (final row in rows) {
      final keys = row.keys.toList()..sort();
      for (final k in keys) {
        buf
          ..write(k)
          ..write('\x00')
          ..write(row[k])
          ..write('\x01');
      }
      buf.write('\x02');
    }
    return buf.toString();
  }

  static String _placeholders(int n) => List.filled(n, '?').join(', ');

  static Variable<Object> _toVariable(Object? value) {
    if (value == null) return const Variable<Object>(null);
    if (value is bool) return Variable<bool>(value);
    if (value is int) return Variable<int>(value);
    if (value is double) return Variable<double>(value);
    return Variable<String>(value.toString());
  }

  /// Force-flush every pending debounced push immediately. Called
  /// before switching active programs so the push queue (which
  /// captured the OLD program's row state) lands in cloud before
  /// the new program's pull fires. Without this, a row edited
  /// 200ms before the switch would never make it to cloud — the
  /// timer fires, but by then the active program has changed and
  /// the upsert lands against the wrong program's filter.
  ///
  /// Caller passes `allSpecs` so the engine can map table names
  /// (the keys in `_pendingPushes` are `"<table>/<id>"`) back to
  /// `TableSpec`s without having to import `sync_specs.dart` (that
  /// would create a circular import).
  Future<void> flushPendingPushes(List<TableSpec> allSpecs) async {
    if (_pendingPushes.isEmpty) return;
    final byName = <String, TableSpec>{
      for (final s in allSpecs) s.table: s,
    };
    final entries = _pendingPushes.entries.toList();
    _pendingPushes.clear();
    final futures = <Future<void>>[];
    for (final e in entries) {
      e.value.cancel();
      final slash = e.key.indexOf('/');
      if (slash <= 0) continue;
      final tableName = e.key.substring(0, slash);
      final id = e.key.substring(slash + 1);
      final spec = byName[tableName];
      if (spec == null) continue;
      futures.add(_pushRowNow(spec, id));
    }
    await Future.wait(futures);
  }

  /// Closes streams + tears down realtime. Called when the
  /// provider disposes (rare; mostly for tests).
  void dispose() {
    for (final timer in _pendingPushes.values) {
      timer.cancel();
    }
    _pendingPushes.clear();
    unawaited(unsubscribeFromRealtime());
    unawaited(_pushErrorController.close());
    unawaited(_realtimeStatusController.close());
  }
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref.read(databaseProvider));
  ref.onDispose(engine.dispose);
  return engine;
});

/// One row's push failure. Emitted on `engine.pushErrors` so the
/// app shell can surface a snackbar / banner — without this,
/// silent 403s (RLS, missing membership) felt like "live sync
/// stopped working" with no signal anywhere.
@immutable
class SyncPushError {
  const SyncPushError({
    required this.table,
    required this.id,
    required this.error,
  });

  final String table;
  final String id;

  /// The thrown error. Usually a `PostgrestException` (with
  /// `.message` / `.code`) for RLS / constraint failures, or a
  /// network exception for offline pushes.
  final Object error;

  /// User-friendly one-line summary suitable for a snackbar.
  /// Strips the more technical wrapping so a teacher sees
  /// "Save failed: row violates row-level security policy"
  /// instead of "PostgrestException(message: ..., code: 42501)".
  String get summary {
    final raw = error.toString();
    // Slice out the message=… field of a PostgrestException to
    // get the bare message. Fallback: full toString.
    final match = RegExp(r'message:\s*([^,)]+)').firstMatch(raw);
    final msg = match?.group(1)?.trim() ?? raw;
    return 'Save failed in $table: $msg';
  }

  @override
  String toString() => 'SyncPushError($table/$id: $error)';
}

/// Snapshot of the realtime layer for the live-indicator widget.
///
/// `isSubscribed` is the connection state — true between
/// `subscribeToRealtime` and `unsubscribeFromRealtime`. False
/// before the first sub or after sign-out.
///
/// `lastEventAt` ticks every time a postgres-change payload
/// hits `_applyRealtimeChange`. The UI renders "Live · 3s ago"
/// using `DateTime.now().difference(lastEventAt)`. Null means
/// "no realtime event has happened in this session" — which can
/// be either "just connected, nothing's changed yet" (fine) or
/// "actually broken" (look at `isSubscribed` to disambiguate).
@immutable
class RealtimeStatus {
  const RealtimeStatus({
    required this.isSubscribed,
    required this.programId,
    required this.lastEventAt,
  });

  final bool isSubscribed;
  final String? programId;
  final DateTime? lastEventAt;

  @override
  String toString() => 'RealtimeStatus(sub=$isSubscribed, '
      'program=$programId, lastEvent=$lastEventAt)';
}
