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
    ChildScheduleOverrides,
    AdultDayBlocks,
    FormSubmissions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 35;

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
          if (from < 29) {
            // v29: per-child expected arrival + pickup times, and a
            // per-(child, date) override table for daily exceptions
            // ("mom texted — running late today"). Both columns on
            // Children default to NULL — existing rows are flexible-
            // schedule kids and never trigger lateness flags.
            await _runSilent(
              'ALTER TABLE "children" '
              'ADD COLUMN "expected_arrival" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "children" '
              'ADD COLUMN "expected_pickup" TEXT NULL',
            );
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "child_schedule_overrides" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"child_id" TEXT NOT NULL '
              'REFERENCES "children"("id") ON DELETE CASCADE, '
              '"date" INTEGER NOT NULL, '
              '"expected_arrival_override" TEXT NULL, '
              '"expected_pickup_override" TEXT NULL, '
              '"note" TEXT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            // One-override-per-day-per-child is enforced at the
            // repository layer (upsert-on-save). An index speeds up
            // the "did Noah have an override today?" lookup every
            // group card does during the flag pass.
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_child_override_child_date" '
              'ON "child_schedule_overrides" ("child_id", "date")',
            );
          }
          if (from < 30) {
            // v30: adult day-timeline. Per-adult-per-day role blocks
            // ('lead' / 'specialist') that subdivide the shift so
            // "group lead 8:30-11, specialist rotator 11-12, back to
            // group lead 12-3" is representable. Gaps are implied off;
            // adults with zero blocks fall back to the static
            // `specialists.adult_role` for compatibility.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "adult_day_blocks" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"specialist_id" TEXT NOT NULL '
              'REFERENCES "specialists"("id") ON DELETE CASCADE, '
              '"day_of_week" INTEGER NOT NULL, '
              '"start_time" TEXT NOT NULL, '
              '"end_time" TEXT NOT NULL, '
              '"role" TEXT NOT NULL, '
              '"pod_id" TEXT NULL '
              'REFERENCES "groups"("id") ON DELETE SET NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            // "What is Sarah doing today?" — one lookup per adult
            // on Today; an index on (specialist_id, day_of_week) keeps
            // the group-card staffing pass O(n) in the block count, not
            // table size.
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_adult_block_specialist_day" '
              'ON "adult_day_blocks" ("specialist_id", "day_of_week")',
            );
            // "Which leads are anchoring Butterflies at 10:15?" — per-
            // group scan during the group card build. Index on (group_id,
            // day_of_week) keeps that pass bounded too.
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_adult_block_pod_day" '
              'ON "adult_day_blocks" ("pod_id", "day_of_week")',
            );
          }
          if (from < 31) {
            // v31: pickup tracking on attendance rows. Two nullable
            // columns — pickup_time (HH:mm) and picked_up_by (free
            // text). The row stays 'present'; a non-null pickup_time
            // just marks the child as collected. Keeps the day's
            // "12/14 present" roll meaningful after pickups start.
            await _runSilent(
              'ALTER TABLE "attendance" '
              'ADD COLUMN "pickup_time" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "attendance" '
              'ADD COLUMN "picked_up_by" TEXT NULL',
            );
          }
          if (from < 35) {
            // v35: second break window on adult availability. v28 added
            // one break + one lunch; some programs run a morning AND
            // afternoon break, so break2_start/end is additive and
            // nullable (any combination of zero/one/two breaks is
            // valid).
            await _runSilent(
              'ALTER TABLE "specialist_availability" '
              'ADD COLUMN "break2_start" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "specialist_availability" '
              'ADD COLUMN "break2_end" TEXT NULL',
            );
          }
          if (from < 34) {
            // v34: polymorphic forms table. One row = one submission
            // of any form type (vehicle_check, behavior_monitoring,
            // future additions). Form-specific fields live in the
            // JSON `data` column; typed columns cover the axes the
            // UI actually queries on (type, status, context, dates).
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "form_submissions" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"form_type" TEXT NOT NULL, '
              "\"status\" TEXT NOT NULL DEFAULT 'draft', "
              '"submitted_at" INTEGER NULL, '
              '"author_name" TEXT NULL, '
              '"child_id" TEXT NULL '
              'REFERENCES "children"("id") ON DELETE SET NULL, '
              '"group_id" TEXT NULL '
              'REFERENCES "groups"("id") ON DELETE SET NULL, '
              '"trip_id" TEXT NULL '
              'REFERENCES "trips"("id") ON DELETE SET NULL, '
              '"parent_submission_id" TEXT NULL '
              'REFERENCES "form_submissions"("id") ON DELETE SET NULL, '
              '"review_due_at" INTEGER NULL, '
              "\"data\" TEXT NOT NULL DEFAULT '{}', "
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            // Indexes for the hot queries: list-by-type (forms hub),
            // child / group timelines (detail screens), and the
            // Today flags scan of review-due-at across all types.
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_form_sub_type" '
              'ON "form_submissions" ("form_type", "submitted_at")',
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_form_sub_child" '
              'ON "form_submissions" ("child_id")',
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_form_sub_parent" '
              'ON "form_submissions" ("parent_submission_id")',
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_form_sub_review_due" '
              'ON "form_submissions" ("review_due_at", "status")',
            );
          }
          if (from < 33) {
            // v33: structural activity-context on observations. Four
            // nullable columns: schedule_source_kind / _id / date
            // pin the observation to the exact scheduled occurrence
            // (template or entry row, on a specific date), and
            // room_id disambiguates which pod's instance of a
            // program-wide activity the observation came from.
            await _runSilent(
              'ALTER TABLE "observations" '
              'ADD COLUMN "schedule_source_kind" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "observations" '
              'ADD COLUMN "schedule_source_id" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "observations" '
              'ADD COLUMN "activity_date" INTEGER NULL',
            );
            await _runSilent(
              'ALTER TABLE "observations" '
              'ADD COLUMN "room_id" TEXT NULL '
              'REFERENCES "rooms"("id") ON DELETE SET NULL',
            );
          }
          if (from < 32) {
            // v32: internal "pod" naming retired in favor of "group"
            // (the word this codebase uses everywhere else). Column +
            // index rename; also updates observations.target_kind
            // values from 'pod' to 'group' so the kind-marker string
            // matches the current vocabulary.
            //
            // SQLite 3.25+ supports RENAME COLUMN; our bundled
            // libraries are well past that. No schema-rewrite needed.
            await _runSilent(
              'ALTER TABLE "adult_day_blocks" '
              'RENAME COLUMN "pod_id" TO "group_id"',
            );
            // Swap the index name to match. Drop-then-recreate is
            // fine; the table is small and this runs once.
            await _runSilent(
              'DROP INDEX IF EXISTS "idx_adult_block_pod_day"',
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_adult_block_group_day" '
              'ON "adult_day_blocks" ("group_id", "day_of_week")',
            );
            // Legacy observations that targeted a group now target a
            // group in the kind-marker string. Plain UPDATE — no
            // data loss.
            await _runSilent(
              'UPDATE "observations" '
              "SET \"target_kind\" = 'group' "
              "WHERE \"target_kind\" = 'pod'",
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
