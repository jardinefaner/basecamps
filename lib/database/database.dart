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
    ObservationKids,
    ObservationAttachments,
    ObservationDomainTags,
    Specialists,
    SpecialistAvailability,
    ActivityLibrary,
    ScheduleTemplates,
    ScheduleEntries,
    TemplatePods,
    EntryPods,
    ParentConcernNotes,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 19;

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
          if (from < 11) {
            await _createTableIfMissing(m, observationKids);
            // Backfill: legacy single-kid observations → join rows.
            await customStatement('''
              INSERT OR IGNORE INTO observation_kids (observation_id, kid_id)
              SELECT id, kid_id FROM observations WHERE kid_id IS NOT NULL
            ''');
          }
          if (from < 12) {
            await _createTableIfMissing(m, observationAttachments);
          }
          if (from < 13) {
            // Remap legacy free-form domains to the SSD / HLTH taxonomy.
            // Unmapped values fall back to 'other'.
            await customStatement(
              "UPDATE observations SET domain = 'ssd8' "
              "WHERE domain = 'social'",
            );
            await customStatement(
              "UPDATE observations SET domain = 'hlth4' "
              "WHERE domain = 'physical'",
            );
            await customStatement(
              "UPDATE observations SET domain = 'ssd4' "
              "WHERE domain = 'behavior'",
            );
            await customStatement(
              "UPDATE observations SET domain = 'other' "
              'WHERE domain NOT IN '
              "('ssd1', 'ssd2', 'ssd3', 'ssd4', 'ssd5', 'ssd6', "
              "'ssd7', 'ssd8', 'ssd9', "
              "'hlth1', 'hlth2', 'hlth3', 'hlth4', 'other')",
            );
          }
          if (from < 14) {
            // Multi-domain tagging. Create the join table, then backfill
            // one row per existing observation so the UI has a list to
            // render immediately — the legacy single-column stays as the
            // "primary" domain written on every save.
            await _createTableIfMissing(m, observationDomainTags);
            await customStatement('''
              INSERT OR IGNORE INTO observation_domain_tags
                (observation_id, domain)
              SELECT id, domain FROM observations WHERE domain IS NOT NULL
            ''');
          }
          if (from < 15) {
            // Avatar support for kids and specialists — local file paths
            // only for now; the image moves to remote storage once a
            // sync story exists.
            await _addColumnIfMissing(m, kids, kids.avatarPath);
            await _addColumnIfMissing(
              m,
              specialists,
              specialists.avatarPath,
            );
          }
          if (from < 16) {
            // First structured form: parent concern notes.
            await _createTableIfMissing(m, parentConcernNotes);
          }
          if (from < 17) {
            // Primary guardian name on a kid (used by the concern note
            // form) + drawn signature paths on each concern note.
            await _addColumnIfMissing(m, kids, kids.parentName);
            await _addColumnIfMissing(
              m,
              parentConcernNotes,
              parentConcernNotes.staffSignaturePath,
            );
            await _addColumnIfMissing(
              m,
              parentConcernNotes,
              parentConcernNotes.supervisorSignaturePath,
            );
          }
          if (from < 18) {
            // Multi-day / date-range entries: a schedule entry can now
            // span several days via the new `end_date` column.
            await _addColumnIfMissing(
              m,
              scheduleEntries,
              scheduleEntries.endDate,
            );
          }
          if (from < 19) {
            // Specialist availability — working hours and time off live
            // in their own table so the specialist detail screen can
            // show "when I work" distinct from "activities I run".
            await _createTableIfMissing(m, specialistAvailability);
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
