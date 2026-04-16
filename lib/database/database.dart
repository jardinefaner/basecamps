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
    ScheduleTemplates,
    ScheduleEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 5;

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
        },
      );
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
