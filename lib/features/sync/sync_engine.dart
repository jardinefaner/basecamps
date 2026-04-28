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

  /// Active realtime channel for the current program. Single channel
  /// multiplexes change events for every spec — cheaper than one
  /// channel per table (each open channel is a heartbeat-burning
  /// presence on the WS). Null when not subscribed (signed out, or
  /// pre-subscribe).
  RealtimeChannel? _realtimeChannel;
  String? _realtimeProgramId;

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

      await client.from(spec.table).upsert(
            _toCloudShape(row, spec.dateColumns),
          );

      for (final cascade in spec.cascades) {
        final cascadeRows = await _readCascadeRows(
          cascade.table,
          cascade.parentColumn,
          id,
        );
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
      }
    } on Object catch (e, st) {
      debugPrint('Sync push failed for ${spec.table}/$id: $e\n$st');
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
  }) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;

    if (_realtimeProgramId == programId && _realtimeChannel != null) {
      return; // Already subscribed for this program.
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
  }

  /// Tears down the current realtime channel. Safe to call when no
  /// channel is open. Invoked by sign-out and by every subscribe
  /// call (so a program-switch transitions cleanly).
  Future<void> unsubscribeFromRealtime() async {
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    _realtimeProgramId = null;
    if (channel == null) return;
    final client = _client;
    if (client == null) return;
    try {
      await client.removeChannel(channel);
    } on Object catch (e) {
      debugPrint('Realtime unsubscribe failed: $e');
    }
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
      await _db.transaction(() async {
        await _upsertLocalRow(spec.table, row, spec.dateColumns);
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

  static String _placeholders(int n) => List.filled(n, '?').join(', ');

  static Variable<Object> _toVariable(Object? value) {
    if (value == null) return const Variable<Object>(null);
    if (value is bool) return Variable<bool>(value);
    if (value is int) return Variable<int>(value);
    if (value is double) return Variable<double>(value);
    return Variable<String>(value.toString());
  }
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(ref.read(databaseProvider));
});
