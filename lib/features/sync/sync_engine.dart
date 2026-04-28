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

  /// Sentinel watermark for first-launch pull (everything > epoch).
  static final DateTime _kEpoch = DateTime.utc(1970);

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  // -- Push --------------------------------------------------------

  /// Pushes the row identified by [id] in [spec] plus all its
  /// cascade rows. Best-effort: catches its own errors and logs
  /// via debugPrint so a failed push doesn't bubble up to the
  /// local-write callsite.
  Future<void> pushRow(TableSpec spec, String id) async {
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
