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

  /// Stream of detected concurrent-edit overwrites. Emits a
  /// [SyncConflict] every time pull or realtime applies a remote
  /// row that's strictly newer than local AND the local row had
  /// been edited since the last successful pull (i.e., local had
  /// unsynced changes when the remote version arrived).
  ///
  /// UI subscribes via `engine.conflicts` and surfaces a snackbar
  /// so a teacher learns "your edit was overwritten by a change
  /// from another device." Last-write-wins is still the semantic
  /// model — this just adds visibility.
  Stream<SyncConflict> get conflicts => _conflictController.stream;
  final StreamController<SyncConflict> _conflictController =
      StreamController<SyncConflict>.broadcast();

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

      // Pre-push freshness check. Without this, two devices
      // editing the same row blindly upsert past each other —
      // last writer wins and the earlier device's changes are
      // silently lost. Fetch the cloud row's updated_at; if
      // cloud is newer than our local copy, abort the push and
      // pull instead so local catches up. Best-effort: if the
      // freshness check itself errors (RLS, network blip, the
      // row doesn't exist yet), fall through to the upsert
      // rather than silently skipping every push.
      final localUpdatedAt = _parseUpdatedAt(row['updated_at']);
      if (localUpdatedAt != null) {
        final cloudUpdatedAt = await _readCloudUpdatedAt(
          client,
          spec.table,
          id,
        );
        if (cloudUpdatedAt != null &&
            cloudUpdatedAt.isAfter(localUpdatedAt)) {
          // Cloud has a newer version. Instead of blindly
          // overwriting (data loss) or blindly aborting (user's
          // edit discarded), do an additive merge: pull cloud's
          // full row, take local non-null fields where cloud is
          // null, push the merged result. Most common scenario
          // is "I added field A on device 1 while another device
          // added field B" — additive merge keeps both.
          //
          // The merge is deliberately conservative: when both
          // sides have a value for the same field, cloud wins
          // (since cloud is newer). True same-field concurrent
          // edits still surface as a conflict toast and one
          // edit loses, but additive scenarios round-trip
          // without loss.
          final cloudRow = await _readCloudRow(client, spec.table, id);
          if (cloudRow != null) {
            final mergedRow = _additiveMerge(
              local: row,
              cloud: cloudRow,
            );
            try {
              await client
                  .from(spec.table)
                  .upsert(_toCloudShape(mergedRow, spec.dateColumns));
              // Update local with the merged result so subsequent
              // edits build on it. The pull below will also run
              // but the merged values are what we just pushed.
              await _upsertLocalRow(spec.table, mergedRow, spec.dateColumns);
              return;
            } on Object catch (e, st) {
              debugPrint(
                'Additive merge push failed for ${spec.table}/$id: '
                '$e\n$st',
              );
              // Fall through to the conflict toast + pull below.
            }
          }
          // Couldn't merge (no cloud row found, merge push
          // failed, etc.) — fall back to the original behavior:
          // emit a conflict toast and pull, accepting that the
          // local edit is lost. Better than blind overwrite.
          if (!_conflictController.isClosed) {
            _conflictController.add(SyncConflict(
              table: spec.table,
              rowId: id,
              localUpdatedAt: localUpdatedAt,
              remoteUpdatedAt: cloudUpdatedAt,
              detectedVia: 'push-precheck',
            ));
          }
          final pid = row['program_id'];
          if (pid is String) {
            unawaited(pullTable(
              spec: spec,
              programId: pid,
              force: true,
            ));
          }
          return;
        }
      }

      await client.from(spec.table).upsert(
            _toCloudShape(row, spec.dateColumns),
          );

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
          // the delete+insert. Real bandwidth save on parent re-
          // pushes that don't touch cascades.
          continue;
        }

        // Cold-start safety: on the first push of this cascade
        // since app launch (no fingerprint cached) AND local has
        // zero cascade rows, refuse to wholesale-DELETE cloud's
        // existing rows. The most likely interpretation of "I'm
        // editing the parent + I have no cascades locally" is
        // "I never pulled the cascades" — not "I deliberately
        // emptied them." Wiping cloud's cascades in that case
        // is silent data loss for the other device that *did*
        // author them. The user can still legitimately empty a
        // cascade by removing the rows on this device first
        // (which sets the fingerprint to the empty hash); this
        // guard only kicks in on the very first cold-start push.
        if (_lastCascadeFingerprint[fingerprintKey] == null &&
            cascadeRows.isEmpty) {
          // Mark the fingerprint so subsequent pushes proceed
          // normally — by then we've either pulled cloud's
          // cascades into local or the user genuinely emptied
          // them locally.
          _lastCascadeFingerprint[fingerprintKey] = fingerprint;
          continue;
        }

        // Replace wholesale. delete-then-upsert is fine within
        // one parent's tiny cascade footprint.
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
      // local edit). Watermark sentinel `_kEpoch` for the first-
      // ever pull means no conflict can fire on a fresh device,
      // which is what we want.
      final preApplyLocalTs = <String, DateTime?>{};
      for (final row in liveRows) {
        preApplyLocalTs[row['id'] as String] =
            await _localUpdatedAt(spec.table, row['id'] as String);
      }

      await _db.transaction(() async {
        if (deletedIds.isNotEmpty) {
          await _db.customUpdate(
            'DELETE FROM "${spec.table}" WHERE id IN (${_placeholders(deletedIds.length)})',
            variables: [for (final id in deletedIds) Variable<String>(id)],
          );
        }
        for (final row in liveRows) {
          await _upsertLocalRow(spec.table, row, spec.dateColumns);
        }
        if (liveRows.isNotEmpty) {
          await _replaceLocalCascades(
            client,
            spec.cascades,
            liveRows.map((r) => r['id'] as String).toList(),
          );
        }
      });

      // Emit conflict events after the txn commits (we don't want
      // listeners reacting to a state that might still get rolled
      // back). Watermark is the value we read at the top of the
      // page loop; rows whose local updated_at is later than that
      // had unsynced edits we just overwrote.
      for (final row in liveRows) {
        final id = row['id'] as String;
        final localTs = preApplyLocalTs[id];
        if (localTs == null) continue;
        final remoteTs =
            DateTime.parse(row['updated_at'] as String).toUtc();
        if (_isConcurrentOverwrite(
          local: localTs,
          remote: remoteTs,
          watermark: watermarkRow?.lastPulledAt,
        )) {
          _conflictController.add(SyncConflict(
            table: spec.table,
            rowId: id,
            localUpdatedAt: localTs,
            remoteUpdatedAt: remoteTs,
            detectedVia: 'pull',
          ));
        }
      }

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

      // Concurrent-edit detection. Realtime has no per-row
      // watermark (only per-table last-pulled-at), so use that as
      // the cutoff. If local updated_at is after the watermark,
      // local had unsynced edits that the incoming change is
      // about to overwrite.
      final watermarkRow = await (_db.select(_db.syncState)
            ..where((s) =>
                s.programId.equals(row['program_id'] as String) &
                s.targetTable.equals(spec.table)))
          .getSingleOrNull();
      final wasConflict = _isConcurrentOverwrite(
        local: localTs,
        remote: remoteUpdatedAt,
        watermark: watermarkRow?.lastPulledAt,
      );

      // Apply parent + re-fetch cascades. One round-trip per
      // cascade table; cheap because the parent event is rare
      // relative to keystroke-rate events.
      await _db.transaction(() async {
        await _upsertLocalRow(spec.table, row, spec.dateColumns);
        if (spec.cascades.isNotEmpty) {
          await _replaceLocalCascades(client, spec.cascades, [id]);
        }
      });

      if (wasConflict && localTs != null) {
        _conflictController.add(SyncConflict(
          table: spec.table,
          rowId: id,
          localUpdatedAt: localTs,
          remoteUpdatedAt: remoteUpdatedAt,
          detectedVia: 'realtime',
        ));
      }
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

  /// Read the full cloud row for [id] in [table]. Used by the
  /// additive merge path on a pre-push conflict — we need cloud's
  /// values for every field to know which ones to keep vs. let
  /// local override. Returns null when the row doesn't exist or
  /// the read fails.
  Future<Map<String, dynamic>?> _readCloudRow(
    SupabaseClient client,
    String table,
    String id,
  ) async {
    try {
      final raw = await client
          .from(table)
          .select()
          .eq('id', id)
          .maybeSingle();
      if (raw == null) return null;
      return Map<String, dynamic>.from(raw);
    } on Object catch (e) {
      debugPrint('Cloud row read failed for $table/$id: $e');
      return null;
    }
  }

  /// Additive merge — combines [local] (the user's pending edit)
  /// with [cloud] (the newer cloud row). Rule per field:
  ///
  ///   * Both null/missing → null.
  ///   * Local null, cloud non-null → cloud (preserve other
  ///     device's value).
  ///   * Local non-null, cloud null → local (preserve user's
  ///     additive edit).
  ///   * Both non-null → cloud (newer wins on same-field
  ///     concurrent edits; user's local change to that field is
  ///     discarded — the conflict toast surfaces this).
  ///
  /// `id`, `created_at`, and `program_id` always take the local
  /// values (these are immutable / row-identity fields). The
  /// merged row's `updated_at` becomes max(local, cloud) so the
  /// resulting upsert reads as "newer than both inputs."
  Map<String, Object?> _additiveMerge({
    required Map<String, Object?> local,
    required Map<String, dynamic> cloud,
  }) {
    final merged = <String, Object?>{};
    final keys = <String>{...local.keys, ...cloud.keys};
    for (final key in keys) {
      final localValue = local[key];
      final cloudValue = cloud[key];
      // Identity / immutable fields — always local.
      if (key == 'id' || key == 'created_at' || key == 'program_id') {
        merged[key] = localValue ?? cloudValue;
        continue;
      }
      // updated_at: take the later of the two so the upsert
      // result reads as newer than both sources.
      if (key == 'updated_at') {
        final localTs = _parseUpdatedAt(localValue);
        final cloudTs = _parseUpdatedAt(cloudValue);
        if (localTs == null) {
          merged[key] = cloudValue;
        } else if (cloudTs == null) {
          merged[key] = localValue;
        } else {
          merged[key] =
              localTs.isAfter(cloudTs) ? localValue : cloudValue;
        }
        continue;
      }
      final localPresent = localValue != null && localValue != '';
      final cloudPresent = cloudValue != null && cloudValue != '';
      if (localPresent && !cloudPresent) {
        merged[key] = localValue;
      } else {
        // Both present, both null, or local-null + cloud-present:
        // defer to cloud.
        merged[key] = cloudValue;
      }
    }
    return merged;
  }

  /// Coerce a row's `updated_at` into a UTC DateTime. Drift hands
  /// back int unix-seconds for date columns; cloud rows arrive as
  /// ISO strings. Both shapes flow through this helper.
  DateTime? _parseUpdatedAt(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

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

  /// Drift returns `int` for DateTime-typed columns (unix-seconds
  /// since drift's encoder). Postgres expects ISO strings. Convert
  /// every column the spec marked as date-typed.
  Map<String, Object?> _toCloudShape(
    Map<String, Object?> row,
    Set<String> dateColumns,
  ) {
    return <String, Object?>{
      for (final entry in row.entries)
        if (dateColumns.contains(entry.key) && entry.value != null)
          entry.key: DateTime.fromMillisecondsSinceEpoch(
            (entry.value! as int) * 1000,
            isUtc: true,
          ).toIso8601String()
        else if (entry.key != 'deleted_at')
          // deleted_at is intentionally not pushed — only
          // pushDelete sets it.
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
    // Skip the cloud-only deleted_at column when projecting back
    // to local — local doesn't carry it.
    final projected = <String, Object?>{};
    for (final entry in row.entries) {
      if (entry.key == 'deleted_at') continue;
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

  /// Detects a concurrent-edit overwrite. Returns true if [local]
  /// is non-null and was modified after [watermark] — meaning the
  /// row had unsynced edits when the [remote] version arrived.
  /// Caller takes the truth and emits a [SyncConflict].
  bool _isConcurrentOverwrite({
    required DateTime? local,
    required DateTime remote,
    required DateTime? watermark,
  }) {
    if (local == null) return false;
    if (watermark == null) return false;
    return local.isAfter(watermark);
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

  /// Closes the conflict stream + tears down realtime. Called
  /// when the provider disposes (rare; mostly for tests).
  void dispose() {
    for (final timer in _pendingPushes.values) {
      timer.cancel();
    }
    _pendingPushes.clear();
    unawaited(unsubscribeFromRealtime());
    unawaited(_conflictController.close());
    unawaited(_pushErrorController.close());
    unawaited(_realtimeStatusController.close());
  }
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref.read(databaseProvider));
  ref.onDispose(engine.dispose);
  return engine;
});

/// One concurrent-edit overwrite. Emitted by the engine when a
/// pull or realtime event applied a remote row that's strictly
/// newer than the local one AND the local row had been edited
/// since the last sync watermark.
///
/// "Concurrent" here means: while we held an unsynced local edit,
/// another device pushed a change to the same row. Last-write-
/// wins picked the remote one (because its updated_at is later);
/// this event lets the UI surface that the local edit got
/// shadowed.
@immutable
class SyncConflict {
  const SyncConflict({
    required this.table,
    required this.rowId,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.detectedVia,
  });

  final String table;
  final String rowId;
  final DateTime localUpdatedAt;
  final DateTime remoteUpdatedAt;

  /// 'pull' (the watermarked pull-on-launch path) or 'realtime'
  /// (the WebSocket subscription). Helps UIs report what surface
  /// the conflict came in through.
  final String detectedVia;

  @override
  String toString() =>
      'SyncConflict($table/$rowId, local=$localUpdatedAt, '
      'remote=$remoteUpdatedAt, via=$detectedVia)';
}

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
