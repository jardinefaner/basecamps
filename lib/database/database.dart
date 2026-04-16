import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'database.g.dart';

QueryExecutor _openConnection() {
  return driftDatabase(name: 'basecamp');
}

@DriftDatabase(
  tables: [
    Pods,
    Kids,
    Trips,
    TripPods,
    Captures,
    CaptureKids,
    Observations,
    Specialists,
    ActivityLibrary,
    ScheduleTemplates,
    ScheduleEntries,
    TemplatePods,
    EntryPods,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // All steps below are idempotent — safe to re-run if an earlier
          // migration partially completed but the schema version wasn't
          // advanced. We swallow "already exists" / "duplicate column" errors
          // so dev databases in inconsistent intermediate states recover.
          if (from < 2) {
            await _createTableIfMissing(m, pods);
            await _createTableIfMissing(m, kids);
          }
          if (from < 3) {
            await _createTableIfMissing(m, trips);
            await _createTableIfMissing(m, captures);
            await _createTableIfMissing(m, captureKids);
            await _createTableIfMissing(m, observations);
          }
          if (from < 4) {
            await _createTableIfMissing(m, scheduleTemplates);
            await _createTableIfMissing(m, scheduleEntries);
          }
          if (from < 5) {
            await _addColumnIfMissing(
              m,
              scheduleTemplates,
              scheduleTemplates.isFullDay,
            );
            await _addColumnIfMissing(
              m,
              scheduleEntries,
              scheduleEntries.isFullDay,
            );
          }
          if (from < 6) {
            await _createTableIfMissing(m, templatePods);
            await _createTableIfMissing(m, entryPods);
            await customStatement('''
              INSERT OR IGNORE INTO template_pods (template_id, pod_id)
              SELECT id, pod_id FROM schedule_templates WHERE pod_id IS NOT NULL
            ''');
            await customStatement('''
              INSERT OR IGNORE INTO entry_pods (entry_id, pod_id)
              SELECT id, pod_id FROM schedule_entries WHERE pod_id IS NOT NULL
            ''');
          }
          if (from < 7) {
            await _createTableIfMissing(m, specialists);
            await _addColumnIfMissing(
              m,
              scheduleTemplates,
              scheduleTemplates.specialistId,
            );
            await _addColumnIfMissing(
              m,
              scheduleEntries,
              scheduleEntries.specialistId,
            );
            // Backfill: promote each distinct legacy specialist_name string
            // into a Specialists row and update referring schedule items.
            // Skip names that already map to a specialist (re-run safety).
            final templateRows = await (select(scheduleTemplates)
                  ..where((t) => t.specialistName.isNotNull()))
                .get();
            final entryRows = await (select(scheduleEntries)
                  ..where((e) => e.specialistName.isNotNull()))
                .get();
            final uniqueNames = <String>{
              ...templateRows.map((r) => r.specialistName!),
              ...entryRows.map((e) => e.specialistName!),
            };
            for (final name in uniqueNames) {
              final existing = await (select(specialists)
                    ..where((s) => s.name.equals(name)))
                  .getSingleOrNull();
              final specialistId = existing?.id ?? newId();
              if (existing == null) {
                await into(specialists).insert(
                  SpecialistsCompanion.insert(id: specialistId, name: name),
                );
              }
              await (update(scheduleTemplates)
                    ..where(
                      (t) =>
                          t.specialistName.equals(name) &
                          t.specialistId.isNull(),
                    ))
                  .write(
                ScheduleTemplatesCompanion(
                  specialistId: Value(specialistId),
                ),
              );
              await (update(scheduleEntries)
                    ..where(
                      (e) =>
                          e.specialistName.equals(name) &
                          e.specialistId.isNull(),
                    ))
                  .write(
                ScheduleEntriesCompanion(
                  specialistId: Value(specialistId),
                ),
              );
            }
          }
          if (from < 8) {
            await _createTableIfMissing(m, activityLibrary);
          }
          if (from < 9) {
            await _addColumnIfMissing(
              m,
              scheduleTemplates,
              scheduleTemplates.startDate,
            );
            await _addColumnIfMissing(
              m,
              scheduleTemplates,
              scheduleTemplates.endDate,
            );
          }
          if (from < 10) {
            await _addColumnIfMissing(
              m,
              trips,
              trips.departureTime,
            );
            await _addColumnIfMissing(
              m,
              trips,
              trips.returnTime,
            );
            await _createTableIfMissing(m, tripPods);
            await _addColumnIfMissing(
              m,
              scheduleEntries,
              scheduleEntries.sourceTripId,
            );
          }
        },
      );

  // Drift's Migrator lacks direct "if exists" helpers. These wrappers catch
  // "table already exists" / "duplicate column name" so upgrades recover from
  // partial runs gracefully.

  static Future<void> _createTableIfMissing(
    Migrator m,
    TableInfo<Table, Object?> table,
  ) async {
    try {
      await m.createTable(table);
    } on Object catch (e) {
      if (_isAlreadyExistsError(e)) return;
      rethrow;
    }
  }

  static Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, Object?> table,
    GeneratedColumn<Object> column,
  ) async {
    try {
      await m.addColumn(table, column);
    } on Object catch (e) {
      if (_isAlreadyExistsError(e)) return;
      rethrow;
    }
  }

  static bool _isAlreadyExistsError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('already exists') ||
        msg.contains('duplicate column');
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
