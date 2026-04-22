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
    Groups,
    Children,
    Trips,
    TripGroups,
    Captures,
    CaptureChildren,
    Observations,
    ObservationChildren,
    ObservationAttachments,
    ObservationDomainTags,
    Specialists,
    SpecialistAvailability,
    Rooms,
    ActivityLibrary,
    ScheduleTemplates,
    ScheduleEntries,
    TemplateGroups,
    EntryGroups,
    ParentConcernNotes,
    ParentConcernChildren,
    Attendance,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 28;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // SQLite turns foreign keys OFF by default per connection, so
        // every onDelete: KeyAction.cascade / setNull we declared on
        // the tables was silently a no-op. Without this, deleting a
        // child left orphaned rows in observation_children /
        // attendance / etc, which surfaced as "deleted children still
        // show up in the observation tag picker."
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Pre-v25 migrations referenced the old "kids/pods" Dart
          // classes and column names (`kids.avatarPath`,
          // `schedule_templates.all_pods`, etc). Those classes no
          // longer exist — v25 renamed them to "children/groups"
          // everywhere. Dev databases below v24 should be wiped
          // rather than force-upgraded; the renames only run if the
          // teacher's DB was already at schema 24.
          if (from < 24) {
            throw UnsupportedError(
              'Schema $from is pre-rename. Wipe the dev database '
              '(uninstall & reinstall) and the app will recreate it '
              'fresh at schema 25. This only affects devs who have '
              'been running the app through old schemas; no end-user '
              'has ever seen schema < 25.',
            );
          }
          if (from < 25) {
            // One-shot rename: every "kid" → "child" and every "pod"
            // → "group" in the schema. Runs against a schema-24 DB
            // from the previous commit; idempotent-enough via
            // try/catch so partial runs recover.
            //
            // Order matters:
            //   1. Rename the existing `schedule_templates.group_id`
            //      (which was the template-series id) to `series_id`
            //      FIRST — otherwise step 2 collides.
            //   2. Rename tables.
            //   3. Rename columns on renamed + untouched tables.
            await _runSilent(
              'ALTER TABLE schedule_templates '
              'RENAME COLUMN "group_id" TO "series_id"',
            );

            await _runSilent('ALTER TABLE "pods" RENAME TO "groups"');
            await _runSilent('ALTER TABLE "kids" RENAME TO "children"');
            await _runSilent(
              'ALTER TABLE "trip_pods" RENAME TO "trip_groups"',
            );
            await _runSilent(
              'ALTER TABLE "capture_kids" RENAME TO "capture_children"',
            );
            await _runSilent(
              'ALTER TABLE "observation_kids" '
              'RENAME TO "observation_children"',
            );
            await _runSilent(
              'ALTER TABLE "template_pods" RENAME TO "template_groups"',
            );
            await _runSilent(
              'ALTER TABLE "entry_pods" RENAME TO "entry_groups"',
            );
            await _runSilent(
              'ALTER TABLE "parent_concern_kids" '
              'RENAME TO "parent_concern_children"',
            );

            // Column renames on the newly-renamed join tables.
            await _runSilent(
              'ALTER TABLE "trip_groups" '
              'RENAME COLUMN "pod_id" TO "group_id"',
            );
            await _runSilent(
              'ALTER TABLE "capture_children" '
              'RENAME COLUMN "kid_id" TO "child_id"',
            );
            await _runSilent(
              'ALTER TABLE "observation_children" '
              'RENAME COLUMN "kid_id" TO "child_id"',
            );
            await _runSilent(
              'ALTER TABLE "template_groups" '
              'RENAME COLUMN "pod_id" TO "group_id"',
            );
            await _runSilent(
              'ALTER TABLE "entry_groups" '
              'RENAME COLUMN "pod_id" TO "group_id"',
            );
            await _runSilent(
              'ALTER TABLE "parent_concern_children" '
              'RENAME COLUMN "kid_id" TO "child_id"',
            );

            // Column renames on tables whose names didn't change.
            await _runSilent(
              'ALTER TABLE "children" '
              'RENAME COLUMN "pod_id" TO "group_id"',
            );
            await _runSilent(
              'ALTER TABLE "observations" '
              'RENAME COLUMN "kid_id" TO "child_id"',
            );
            await _runSilent(
              'ALTER TABLE "observations" '
              'RENAME COLUMN "pod_id" TO "group_id"',
            );
            await _runSilent(
              'ALTER TABLE "schedule_templates" '
              'RENAME COLUMN "pod_id" TO "group_id"',
            );
            await _runSilent(
              'ALTER TABLE "schedule_templates" '
              'RENAME COLUMN "all_pods" TO "all_groups"',
            );
            await _runSilent(
              'ALTER TABLE "schedule_entries" '
              'RENAME COLUMN "pod_id" TO "group_id"',
            );
            await _runSilent(
              'ALTER TABLE "schedule_entries" '
              'RENAME COLUMN "all_pods" TO "all_groups"',
            );
            await _runSilent(
              'ALTER TABLE "attendance" '
              'RENAME COLUMN "kid_id" TO "child_id"',
            );
          }
          if (from < 26) {
            // v26: rich activity-card fields. Adding nullable columns
            // is safe on existing rows — legacy preset items keep NULL
            // and render as plain tiles; new AI-generated cards fill
            // them in.
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "audience_min_age" INTEGER NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "audience_max_age" INTEGER NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "hook" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "summary" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "key_points" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "learning_goals" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "engagement_time_min" INTEGER NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "source_url" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "source_attribution" TEXT NULL',
            );
          }
          if (from < 27) {
            // v27: link scheduled rows back to their source library
            // card (when created via "From library"). Lets the Today
            // detail sheet's title tap drill into the rich library
            // content without losing the schedule context. Nullable
            // + FK setNull on library delete.
            await _runSilent(
              'ALTER TABLE "schedule_templates" '
              'ADD COLUMN "source_library_item_id" TEXT NULL '
              'REFERENCES "activity_library"("id") ON DELETE SET NULL',
            );
            await _runSilent(
              'ALTER TABLE "schedule_entries" '
              'ADD COLUMN "source_library_item_id" TEXT NULL '
              'REFERENCES "activity_library"("id") ON DELETE SET NULL',
            );
          }
          if (from < 28) {
            // v28: adults (lead/specialist/ambient roles + anchor) and
            // rooms (tracked entities for collision detection).
            //
            // Specialists gain two columns:
            //   - adult_role: 'lead' | 'specialist' | 'ambient'
            //     (defaults to 'specialist' so existing rows keep
            //     their current rover behavior)
            //   - anchored_group_id: for leads, which group they stay
            //     with. Nullable, setNull on group delete.
            await _runSilent(
              'ALTER TABLE "specialists" '
              "ADD COLUMN \"adult_role\" TEXT NOT NULL DEFAULT 'specialist'",
            );
            await _runSilent(
              'ALTER TABLE "specialists" '
              'ADD COLUMN "anchored_group_id" TEXT NULL '
              'REFERENCES "groups"("id") ON DELETE SET NULL',
            );
            // Break + lunch on each availability row, all nullable
            // HH:MM strings same as start/end time.
            await _runSilent(
              'ALTER TABLE "specialist_availability" '
              'ADD COLUMN "break_start" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "specialist_availability" '
              'ADD COLUMN "break_end" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "specialist_availability" '
              'ADD COLUMN "lunch_start" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "specialist_availability" '
              'ADD COLUMN "lunch_end" TEXT NULL',
            );
            // New rooms table. onCreate isn't called during upgrade —
            // we build it by hand matching the Drift-generated DDL.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "rooms" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"name" TEXT NOT NULL, '
              '"capacity" INTEGER NULL, '
              '"notes" TEXT NULL, '
              '"default_for_group_id" TEXT NULL '
              'REFERENCES "groups"("id") ON DELETE SET NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            // Templates and entries gain a roomId FK — nullable so
            // legacy rows keep their free-form location string
            // untouched. When both are set, room wins for conflict
            // detection; location stays as the display fallback.
            await _runSilent(
              'ALTER TABLE "schedule_templates" '
              'ADD COLUMN "room_id" TEXT NULL '
              'REFERENCES "rooms"("id") ON DELETE SET NULL',
            );
            await _runSilent(
              'ALTER TABLE "schedule_entries" '
              'ADD COLUMN "room_id" TEXT NULL '
              'REFERENCES "rooms"("id") ON DELETE SET NULL',
            );
          }
        },
      );

  /// Runs `stmt` and swallows "duplicate column / no such column /
  /// already exists" errors so re-running the rename migration after
  /// a partial failure is safe. Anything else surfaces.
  Future<void> _runSilent(String stmt) async {
    try {
      await customStatement(stmt);
    } on Object catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('no such column') ||
          msg.contains('no such table') ||
          msg.contains('already exists') ||
          msg.contains('duplicate column')) {
        return;
      }
      rethrow;
    }
  }

}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
