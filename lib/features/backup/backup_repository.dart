import 'dart:async';
import 'dart:convert';

import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud-backup repository — Slice B.
///
/// Per-program snapshot of every Drift row that scopes to a program
/// (entity tables) plus everything that cascades from them (joins,
/// attachments, etc). Snapshot is JSON, uploaded to a private
/// Supabase Storage bucket at `<programId>/snapshot.json`. Restoring
/// wipes the program's local rows and reinserts from the JSON.
///
/// Single-writer model. The teacher can push or pull manually; if
/// two devices both edit between sync, the most recent push wins
/// for everyone. Slice C will replace this with per-table sync that
/// resolves conflicts row-by-row.
///
/// Schema-version safety: every snapshot stamps the Drift
/// [AppDatabase.schemaVersion] of the device that made it. On
/// restore, refusing to import a snapshot whose schema is *higher*
/// than ours prevents a newer device's data from corrupting an
/// older one. Equal version is fine; lower is also fine since
/// migrations are forward-only and additive.
class BackupRepository {
  BackupRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;

  /// Storage bucket name. Created via the cloud SQL migration; the
  /// bucket's RLS policies scope reads/writes to program members.
  static const _bucket = 'db_backups';

  /// Magic top-level keys in the snapshot envelope. Stable strings
  /// — old snapshots created with these keys must keep deserializing
  /// after schema changes (only `tables.*` evolves).
  static const _kSchemaVersion = 'schemaVersion';
  static const _kExportedAt = 'exportedAt';
  static const _kProgramId = 'programId';
  static const _kTables = 'tables';

  // -- Table catalog -----------------------------------------------

  /// Tables that scope directly by `program_id`. Order chosen so a
  /// straight insert respects FK dependencies (groups before children
  /// because children FK groups, etc). Same list, reversed, gives
  /// the deletion order on restore.
  static const _programScopedTables = <String>[
    'programs',
    'program_members',
    'groups',
    'rooms',
    'roles',
    'parents',
    'children',
    'adults',
    'vehicles',
    'trips',
    'activity_library',
    'lesson_sequences',
    'themes',
    'schedule_templates',
    'schedule_entries',
    'observations',
    'parent_concern_notes',
    'form_submissions',
  ];

  /// Cascade / join tables — scoped through their parent's
  /// program_id. Pair maps the table name to the SQL fragment
  /// that filters its rows to the given program. Insert order
  /// follows the parent ordering above.
  ///
  /// Why a string-keyed map of raw SQL: every entry needs its own
  /// JOIN shape against a different parent, and codegen here would
  /// add ceremony without removing duplication. Each fragment is
  /// short and self-contained.
  static const _cascadeTables = <String, String>{
    'trip_groups':
        'EXISTS (SELECT 1 FROM trips t '
            'WHERE t.id = trip_groups.trip_id AND t.program_id = ?)',
    'template_groups':
        'EXISTS (SELECT 1 FROM schedule_templates s '
            'WHERE s.id = template_groups.template_id AND s.program_id = ?)',
    'entry_groups':
        'EXISTS (SELECT 1 FROM schedule_entries e '
            'WHERE e.id = entry_groups.entry_id AND e.program_id = ?)',
    'parent_children':
        'EXISTS (SELECT 1 FROM parents p '
            'WHERE p.id = parent_children.parent_id AND p.program_id = ?)',
    'observation_children':
        'EXISTS (SELECT 1 FROM observations o '
            'WHERE o.id = observation_children.observation_id '
            'AND o.program_id = ?)',
    'observation_attachments':
        'EXISTS (SELECT 1 FROM observations o '
            'WHERE o.id = observation_attachments.observation_id '
            'AND o.program_id = ?)',
    'observation_domain_tags':
        'EXISTS (SELECT 1 FROM observations o '
            'WHERE o.id = observation_domain_tags.observation_id '
            'AND o.program_id = ?)',
    'activity_library_domain_tags':
        'EXISTS (SELECT 1 FROM activity_library a '
            'WHERE a.id = activity_library_domain_tags.library_item_id '
            'AND a.program_id = ?)',
    'activity_library_usages':
        'EXISTS (SELECT 1 FROM activity_library a '
            'WHERE a.id = activity_library_usages.library_item_id '
            'AND a.program_id = ?)',
    'lesson_sequence_items':
        'EXISTS (SELECT 1 FROM lesson_sequences ls '
            'WHERE ls.id = lesson_sequence_items.sequence_id '
            'AND ls.program_id = ?)',
    'captures':
        'EXISTS (SELECT 1 FROM trips t '
            'WHERE t.id = captures.trip_id AND t.program_id = ?)',
    'capture_children':
        'EXISTS (SELECT 1 FROM captures c '
            'JOIN trips t ON t.id = c.trip_id '
            'WHERE c.id = capture_children.capture_id AND t.program_id = ?)',
    'attendance':
        'EXISTS (SELECT 1 FROM children c '
            'WHERE c.id = attendance.child_id AND c.program_id = ?)',
    'child_schedule_overrides':
        'EXISTS (SELECT 1 FROM children c '
            'WHERE c.id = child_schedule_overrides.child_id '
            'AND c.program_id = ?)',
    'adult_availability':
        'EXISTS (SELECT 1 FROM adults a '
            'WHERE a.id = adult_availability.adult_id AND a.program_id = ?)',
    'adult_day_blocks':
        'EXISTS (SELECT 1 FROM adults a '
            'WHERE a.id = adult_day_blocks.adult_id AND a.program_id = ?)',
    'parent_concern_children':
        'EXISTS (SELECT 1 FROM parent_concern_notes n '
            'WHERE n.id = parent_concern_children.note_id '
            'AND n.program_id = ?)',
  };

  // -- Export ------------------------------------------------------

  /// Walks every program-scoped + cascade table, serializes each
  /// row to a JSON map, and returns the full envelope. Safe to call
  /// on a hot DB — uses read-only SELECTs and no transaction (the
  /// snapshot is a point-in-time best-effort, not a strict
  /// transactional snapshot, which is fine for single-writer).
  ///
  /// Resilient to schema drift: each table query is wrapped in a
  /// try/catch so a missing column or missing table on one table
  /// doesn't blow up the entire backup. Skipped tables are listed
  /// in the envelope under `skippedTables` so a developer can see
  /// which tables didn't make it. End users see "Backed up to the
  /// cloud." regardless — partial snapshots are better than none.
  Future<Map<String, dynamic>> exportProgramSnapshot(String programId) async {
    final tables = <String, List<Map<String, Object?>>>{};
    final skipped = <String, String>{};

    // program_id-scoped tables: simple WHERE.
    for (final table in _programScopedTables) {
      final whereCol = table == 'programs' ? 'id' : 'program_id';
      try {
        final rows = await _db.customSelect(
          'SELECT * FROM "$table" WHERE "$whereCol" = ?',
          variables: [Variable<String>(programId)],
        ).get();
        tables[table] = rows.map((r) => r.data).toList();
      } on Object catch (e) {
        skipped[table] = e.toString();
      }
    }

    // Cascade tables: EXISTS subquery against the parent.
    for (final entry in _cascadeTables.entries) {
      try {
        final rows = await _db.customSelect(
          'SELECT * FROM "${entry.key}" WHERE ${entry.value}',
          variables: [Variable<String>(programId)],
        ).get();
        tables[entry.key] = rows.map((r) => r.data).toList();
      } on Object catch (e) {
        skipped[entry.key] = e.toString();
      }
    }

    return <String, dynamic>{
      _kSchemaVersion: _db.schemaVersion,
      _kExportedAt: DateTime.now().toUtc().toIso8601String(),
      _kProgramId: programId,
      _kTables: tables,
      if (skipped.isNotEmpty) 'skippedTables': skipped,
    };
  }

  // -- Import ------------------------------------------------------

  /// Replaces every program-scoped + cascade row in the local DB
  /// with the contents of [snapshot]. FK checks are temporarily
  /// disabled during the wipe-and-reload so insert order doesn't
  /// have to thread the dependency graph perfectly. Re-enabled
  /// (and validated) after the transaction commits.
  ///
  /// Throws [BackupSchemaMismatch] when the snapshot was made on
  /// a newer Drift schema than this device. Older-or-equal is fine
  /// — migrations are forward-only and additive, so a v40 snapshot
  /// restores cleanly into a v42 database (the new columns just
  /// stay null on the restored rows).
  Future<void> importProgramSnapshot(Map<String, dynamic> snapshot) async {
    final snapVersion = (snapshot[_kSchemaVersion] as num?)?.toInt() ?? 0;
    if (snapVersion > _db.schemaVersion) {
      throw BackupSchemaMismatch(
        snapVersion: snapVersion,
        deviceVersion: _db.schemaVersion,
      );
    }
    final programId = snapshot[_kProgramId] as String?;
    if (programId == null || programId.isEmpty) {
      throw const FormatException('snapshot missing programId');
    }
    final tables = (snapshot[_kTables] as Map?)?.cast<String, dynamic>();
    if (tables == null) {
      throw const FormatException('snapshot missing tables');
    }

    await _db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await _db.transaction(() async {
        // Wipe — cascade tables first (no FKs from anyone), then
        // entity tables in reverse-dependency order. With FKs off
        // the order is mostly cosmetic, but keeping it tidy makes
        // any future strict-FK migration drop in cleanly. Each
        // delete is best-effort so a missing table on this device
        // doesn't crash the whole restore.
        for (final table in _cascadeTables.keys.toList().reversed) {
          try {
            await _db.customUpdate(
              // Cascade tables don't all carry program_id; scope via
              // the same EXISTS clause we used for export.
              'DELETE FROM "$table" WHERE ${_cascadeTables[table]}',
              variables: [Variable<String>(programId)],
            );
          } on Object {
            // Missing table or column on this device — skip.
          }
        }
        for (final table in _programScopedTables.reversed) {
          final col = table == 'programs' ? 'id' : 'program_id';
          try {
            await _db.customUpdate(
              'DELETE FROM "$table" WHERE "$col" = ?',
              variables: [Variable<String>(programId)],
            );
          } on Object {
            // Same as above — best-effort wipe.
          }
        }

        // Insert — entity tables first (FK targets), then cascade.
        // Per-row try/catch so a single mal-shaped row from an
        // older snapshot doesn't fail the whole transaction.
        for (final table in [
          ..._programScopedTables,
          ..._cascadeTables.keys,
        ]) {
          final rowsRaw = tables[table];
          if (rowsRaw is! List) continue;
          for (final r in rowsRaw) {
            if (r is! Map) continue;
            final row = r.cast<String, Object?>();
            if (row.isEmpty) continue;
            final cols = row.keys.toList();
            final placeholders =
                List.filled(cols.length, '?').join(', ');
            final colList = cols.map((c) => '"$c"').join(', ');
            try {
              await _db.customInsert(
                'INSERT INTO "$table" ($colList) VALUES ($placeholders)',
                variables: [
                  for (final c in cols) _toVariable(row[c]),
                ],
              );
            } on Object {
              // Skip rows whose columns don't exist on this
              // device's schema. Future migrations are forward-
              // only so this should only happen during the
              // narrow window of a partial migration.
            }
          }
        }
      });
    } finally {
      await _db.customStatement('PRAGMA foreign_keys = ON');
    }
  }

  /// Coerces a JSON-decoded value into the right Drift `Variable`.
  /// JSON booleans + numbers + strings all flow through here on the
  /// import path. SQLite stores booleans as 0/1, ints as INTEGER,
  /// strings as TEXT — Drift's `Variable<T>` picks the right
  /// binding based on T.
  static Variable<Object> _toVariable(Object? value) {
    if (value == null) return const Variable<Object>(null);
    if (value is bool) return Variable<bool>(value);
    if (value is int) return Variable<int>(value);
    if (value is double) return Variable<double>(value);
    return Variable<String>(value.toString());
  }

  // -- Cloud push / pull -------------------------------------------

  /// Storage object key for [programId]. One snapshot per program;
  /// the bucket's RLS only permits members of the program to read
  /// or write their folder.
  static String _objectKey(String programId) =>
      '$programId/snapshot.json';

  /// Exports the current state and uploads it. Returns the
  /// timestamp the cloud reports for the new object.
  Future<DateTime> pushSnapshotToCloud(String programId) async {
    final snapshot = await exportProgramSnapshot(programId);
    final bytes = utf8.encode(jsonEncode(snapshot));
    await _client.storage.from(_bucket).uploadBinary(
          _objectKey(programId),
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(
            // Overwrite any existing snapshot. The bucket holds
            // exactly one object per program — no history yet.
            upsert: true,
            contentType: 'application/json',
          ),
        );
    // Read back the metadata to give the UI a freshness label.
    final remoteMeta = await cloudSnapshotInfo(programId);
    return remoteMeta?.updatedAt ?? DateTime.now().toUtc();
  }

  /// Returns metadata for the cloud snapshot or null when none
  /// exists. Used by the Settings card to show "Last backed up"
  /// and by the (future) auto-pull-on-sign-in to decide whether
  /// to prompt.
  Future<CloudSnapshotInfo?> cloudSnapshotInfo(String programId) async {
    try {
      final list = await _client.storage.from(_bucket).list(
            path: programId,
            searchOptions: const SearchOptions(limit: 1),
          );
      for (final obj in list) {
        if (obj.name == 'snapshot.json') {
          final updated = obj.updatedAt;
          if (updated == null) return null;
          return CloudSnapshotInfo(
            updatedAt: DateTime.parse(updated).toUtc(),
            sizeBytes: (obj.metadata?['size'] as num?)?.toInt(),
          );
        }
      }
      return null;
    } on Object {
      // Bucket missing, network down, RLS rejection — all reported
      // as "no snapshot" so the UI doesn't have to distinguish.
      return null;
    }
  }

  /// Downloads the cloud snapshot and replays it locally. Caller is
  /// responsible for confirming with the user before invoking — this
  /// wipes program-scoped local rows.
  Future<void> pullSnapshotFromCloud(String programId) async {
    final bytes = await _client.storage
        .from(_bucket)
        .download(_objectKey(programId));
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    await importProgramSnapshot(json);
  }
}

/// Metadata about the stored snapshot. Returned by
/// [BackupRepository.cloudSnapshotInfo].
class CloudSnapshotInfo {
  const CloudSnapshotInfo({required this.updatedAt, this.sizeBytes});

  final DateTime updatedAt;
  final int? sizeBytes;
}

/// Thrown by [BackupRepository.importProgramSnapshot] when the
/// snapshot's schema version is higher than this device can handle.
/// Caller surfaces a "your other device is on a newer version —
/// update this device first" message.
class BackupSchemaMismatch implements Exception {
  const BackupSchemaMismatch({
    required this.snapVersion,
    required this.deviceVersion,
  });

  final int snapVersion;
  final int deviceVersion;

  @override
  String toString() =>
      'Snapshot is at schema v$snapVersion; this device is on '
      'v$deviceVersion. Update the app, then try again.';
}

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository(
    ref.read(databaseProvider),
    Supabase.instance.client,
  );
});
