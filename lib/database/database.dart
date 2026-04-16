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
    Captures,
    CaptureKids,
    Observations,
    Specialists,
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
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(pods);
            await m.createTable(kids);
          }
          if (from < 3) {
            await m.createTable(trips);
            await m.createTable(captures);
            await m.createTable(captureKids);
            await m.createTable(observations);
          }
          if (from < 4) {
            await m.createTable(scheduleTemplates);
            await m.createTable(scheduleEntries);
          }
          if (from < 5) {
            await m.addColumn(scheduleTemplates, scheduleTemplates.isFullDay);
            await m.addColumn(scheduleEntries, scheduleEntries.isFullDay);
          }
          if (from < 6) {
            await m.createTable(templatePods);
            await m.createTable(entryPods);
            await customStatement('''
              INSERT INTO template_pods (template_id, pod_id)
              SELECT id, pod_id FROM schedule_templates WHERE pod_id IS NOT NULL
            ''');
            await customStatement('''
              INSERT INTO entry_pods (entry_id, pod_id)
              SELECT id, pod_id FROM schedule_entries WHERE pod_id IS NOT NULL
            ''');
          }
          if (from < 7) {
            await m.createTable(specialists);
            await m.addColumn(
              scheduleTemplates,
              scheduleTemplates.specialistId,
            );
            await m.addColumn(
              scheduleEntries,
              scheduleEntries.specialistId,
            );
            // Backfill: promote each distinct legacy specialist_name string
            // into a Specialists row and update referring schedule items.
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
              final specialistId = newId();
              await into(specialists).insert(
                SpecialistsCompanion.insert(id: specialistId, name: name),
              );
              await (update(scheduleTemplates)
                    ..where((t) => t.specialistName.equals(name)))
                  .write(
                ScheduleTemplatesCompanion(
                  specialistId: Value(specialistId),
                ),
              );
              await (update(scheduleEntries)
                    ..where((e) => e.specialistName.equals(name)))
                  .write(
                ScheduleEntriesCompanion(
                  specialistId: Value(specialistId),
                ),
              );
            }
          }
        },
      );
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
