import 'dart:convert';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/tables.dart';
import 'package:basecamp/features/sync/synced_tables.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'database.g.dart';

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'basecamp',
    // Web build needs explicit WASM + worker URIs; native builds
    // ignore this parameter and use the platform's sqlite3 binding.
    // The two files (sqlite3.wasm + drift_worker.js) are committed
    // into web/ so the bundle ships with them. See web/README.md
    // (or drift_dev's `make-defaults` command) for regenerating
    // them when drift bumps.
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
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
    Adults,
    AdultAvailability,
    Rooms,
    ActivityLibrary,
    ScheduleTemplates,
    ScheduleEntries,
    TemplateGroups,
    EntryGroups,
    Attendance,
    ChildScheduleOverrides,
    AdultDayBlocks,
    FormSubmissions,
    Vehicles,
    Parents,
    ParentChildren,
    Roles,
    ActivityLibraryDomainTags,
    ActivityLibraryUsages,
    LessonSequences,
    LessonSequenceItems,
    Themes,
    Programs,
    ProgramMembers,
    SyncState,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 45;

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
          // Schema-heal: re-apply the v42 ALTER TABLE for any
          // entity table that's still missing `program_id`. Some
          // users' local DBs ended up with a partial v42 migration
          // (web IndexedDB closed mid-upgrade, native app force-
          // killed during launch), and any later insert that tries
          // to stamp program_id on the gap-table fails silently.
          // Running this every launch is cheap (the ALTER is a
          // no-op when the column already exists, swallowed by
          // _runSilent).
          await _healProgramIdColumns();
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
          if (from < 45) {
            // v45: retire the bespoke parent_concern_notes +
            // parent_concern_children tables. The polymorphic
            // form_submissions row with form_type='parent_concern'
            // (commit 3784201) replaces them.
            //
            // Carry any local rows forward into form_submissions
            // first — re-runnable via INSERT OR REPLACE since the
            // form_submissions row stamps the same id as the
            // bespoke row, and the previous app-level migration
            // (parent_concern_migration.dart) used the same key.
            //
            // After the data move, drop both tables. SQLite's
            // foreign_keys=ON would block dropping a parent
            // referenced by a (now-empty) cascade table; turn it
            // off for the duration of the transition and re-enable
            // afterwards.
            await _migrateParentConcernRowsToFormSubmissions();
            await _runSilent('PRAGMA foreign_keys = OFF');
            await _runSilent(
              'DROP TABLE IF EXISTS "parent_concern_children"',
            );
            await _runSilent(
              'DROP TABLE IF EXISTS "parent_concern_notes"',
            );
            await _runSilent('PRAGMA foreign_keys = ON');
          }
          if (from < 44) {
            // v44: storage_path columns for media sync. Nullable
            // additive — existing rows have null storage_path
            // until MediaService.upload sends their local file
            // to cloud. On other devices, readers fall back from
            // localPath (no file) to storage_path (download on
            // demand).
            await _runSilent(
              'ALTER TABLE "observation_attachments" '
              'ADD COLUMN "storage_path" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "children" '
              'ADD COLUMN "avatar_storage_path" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "adults" '
              'ADD COLUMN "avatar_storage_path" TEXT NULL',
            );
          }
          if (from < 43) {
            // v43: per-table sync watermark for Slice C. Tracks
            // the latest updated_at seen from cloud per (program,
            // table) so pull-on-launch only fetches deltas. No
            // backfill — empty table is fine; queries default the
            // sentinel watermark to epoch when no row exists.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "sync_state" ( '
              '"program_id" TEXT NOT NULL, '
              '"target_table" TEXT NOT NULL, '
              '"last_pulled_at" INTEGER NOT NULL, '
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              'PRIMARY KEY ("program_id", "target_table")'
              ' )',
            );
          }
          if (from < 42) {
            // v42: stamp every entity table with a nullable
            // `program_id`. Additive, no NOT NULL constraint yet —
            // existing rows stay untagged until the auth bootstrap
            // runs a one-shot backfill (see ProgramsRepository
            // .backfillUntaggedRows). Repositories start carrying
            // the active program id on inserts from this version
            // forward; reads remain program-agnostic until Slice C
            // adds RLS-style filters.
            //
            // Joins / cascade-children tables (TripGroups,
            // TemplateGroups, EntryGroups, ParentChildren,
            // ObservationChildren / -Attachments / -DomainTags,
            // CaptureChildren, ParentConcernChildren,
            // AdultAvailability, AdultDayBlocks,
            // ChildScheduleOverrides, Attendance, Captures,
            // ActivityLibraryDomainTags, ActivityLibraryUsages,
            // LessonSequenceItems) intentionally do NOT get a
            // program_id — they belong to whichever parent row
            // already carries one.
            for (final t in kSyncedTableNames) {
              await _runSilent(
                'ALTER TABLE "$t" ADD COLUMN "program_id" TEXT NULL',
              );
              await _runSilent(
                'CREATE INDEX IF NOT EXISTS '
                '"idx_${t}_program" '
                'ON "$t" ("program_id")',
              );
            }
          }
          if (from < 41) {
            // v41: introduce the program scaffold. Programs are the
            // unit of sharing in the multi-user model — every
            // existing data table will eventually carry a
            // `program_id` (a later migration), so a single Supabase
            // database can host many programs without leaking data
            // across them. v41 only lays down the two membership
            // tables; the column-stamping comes once we ship Slice C.
            //
            // No backfill here. Existing local rows stay untagged
            // until the user signs in, at which point the auth
            // bootstrap creates a default program and tags
            // everything with it. That bootstrap lives outside the
            // migration so it can run after the auth session is
            // available (migrations run during DB open, before any
            // network is touched).
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "programs" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"name" TEXT NOT NULL, '
              '"created_by" TEXT NOT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "program_members" ( '
              '"program_id" TEXT NOT NULL '
              'REFERENCES "programs"("id") ON DELETE CASCADE, '
              '"user_id" TEXT NOT NULL, '
              '"role" TEXT NOT NULL DEFAULT \'teacher\', '
              '"joined_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              'PRIMARY KEY ("program_id", "user_id")'
              ' )',
            );
            // Lookup index: "what programs is this user in?" runs on
            // every active-program resolution and the future invite
            // flow. (program_id, user_id) PK already covers the
            // forward direction; this covers the reverse.
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_program_members_user" '
              'ON "program_members" ("user_id")',
            );
          }
          if (from < 40) {
            // v40: omnibus additive migration covering the next few
            // rounds of work — adult contact info + staff↔parent
            // bridge, per-activity source URLs, and scaffolding for
            // library domain tags, usage tracking, lesson sequences,
            // and themes. All additive; no data back-fills needed.
            await _runSilent(
              'ALTER TABLE "adults" '
              'ADD COLUMN "phone" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "adults" '
              'ADD COLUMN "email" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "adults" '
              'ADD COLUMN "parent_id" TEXT NULL '
              'REFERENCES "parents"("id") ON DELETE SET NULL',
            );
            await _runSilent(
              'ALTER TABLE "schedule_templates" '
              'ADD COLUMN "source_url" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "schedule_entries" '
              'ADD COLUMN "source_url" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "materials" TEXT NULL',
            );
            // Join: free-text domain tags per library item. No UI
            // this round; Round 2 consumes.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS '
              '"activity_library_domain_tags" ( '
              '"library_item_id" TEXT NOT NULL '
              'REFERENCES "activity_library"("id") ON DELETE CASCADE, '
              '"domain" TEXT NOT NULL, '
              'PRIMARY KEY ("library_item_id", "domain")'
              ' )',
            );
            // Usage log — one row per instantiation of a library card.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS '
              '"activity_library_usages" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"library_item_id" TEXT NOT NULL '
              'REFERENCES "activity_library"("id") ON DELETE CASCADE, '
              '"template_id" TEXT NULL '
              'REFERENCES "schedule_templates"("id") ON DELETE SET NULL, '
              '"entry_id" TEXT NULL '
              'REFERENCES "schedule_entries"("id") ON DELETE SET NULL, '
              '"used_on" INTEGER NOT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            // Hot query: "recently used" sort on the library card
            // tile — one lookup per card during the library screen
            // render. Index on (library_item_id) keeps that bounded.
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_library_usages_item" '
              'ON "activity_library_usages" ("library_item_id")',
            );
            // Lesson sequences + their ordered items. No UI this
            // round; Round 4 builds the planner on top.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "lesson_sequences" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"name" TEXT NOT NULL, '
              '"description" TEXT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "lesson_sequence_items" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"sequence_id" TEXT NOT NULL '
              'REFERENCES "lesson_sequences"("id") ON DELETE CASCADE, '
              '"library_item_id" TEXT NOT NULL '
              'REFERENCES "activity_library"("id") ON DELETE CASCADE, '
              '"position" INTEGER NOT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            // Themes. Standalone table; later rounds can join.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "themes" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"name" TEXT NOT NULL, '
              '"color_hex" TEXT NULL, '
              '"start_date" INTEGER NOT NULL, '
              '"end_date" INTEGER NOT NULL, '
              '"notes" TEXT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
          }
          if (from < 39) {
            // v39: staff roles promoted from a free-text
            // `adults.role` column into a first-class Roles entity.
            // Existing adults keep their free-text blurb as a
            // display fallback; new rows go through `adults.role_id`
            // populated by the picker. Distinct non-empty legacy
            // role strings are materialized as Role rows here and
            // each adult is relinked by roleId.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "roles" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"name" TEXT NOT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            await _runSilent(
              'ALTER TABLE "adults" '
              'ADD COLUMN "role_id" TEXT NULL '
              'REFERENCES "roles"("id") ON DELETE SET NULL',
            );
            // Backfill: grab distinct non-empty role strings from
            // adults, materialize one Role row per string, then
            // UPDATE every matching adult row to point at it.
            final distinct = await customSelect(
              'SELECT DISTINCT TRIM("role") AS label FROM "adults" '
              'WHERE "role" IS NOT NULL AND TRIM("role") != \'\'',
            ).get();
            for (final row in distinct) {
              final label = row.read<String>('label');
              final id = newId();
              await customStatement(
                'INSERT INTO "roles" ("id", "name") VALUES (?, ?)',
                [id, label],
              );
              await customStatement(
                'UPDATE "adults" SET "role_id" = ? '
                'WHERE TRIM("role") = ?',
                [id, label],
              );
            }
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
            // The adults table (named "specialists" pre-v36) gains two columns:
            //   - adult_role: 'lead' | 'adult' | 'ambient'
            //     (defaults to 'adult' so existing rows keep
            //     their current rover behavior)
            //   - anchored_group_id: for leads, which group they stay
            //     with. Nullable, setNull on group delete.
            await _runSilent(
              'ALTER TABLE "specialists" '
              "ADD COLUMN \"adult_role\" TEXT NOT NULL DEFAULT 'adult'",
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
            // "group lead 8:30-11, adult rotator 11-12, back to
            // group lead 12-3" is representable. Gaps are implied off;
            // adults with zero blocks fall back to the static
            // `adults.adult_role` for compatibility.
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
          // --- version gates below ---
          if (from < 38) {
            // v38: parents / guardians as a first-class entity. Two
            // new tables — parents (the row) and parent_children
            // (many-to-many so siblings share a single parent row,
            // and a child with two parents gets two join rows).
            //
            // Existing Children.parentName stays — it's free text,
            // not a FK, and still works for programs that haven't
            // promoted to the new Parents entity yet. A future
            // migration can auto-create Parent rows from non-empty
            // parentName values; deferring that until the UI fully
            // shifts to the picker.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "parents" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"first_name" TEXT NOT NULL, '
              '"last_name" TEXT NULL, '
              '"relationship" TEXT NULL, '
              '"phone" TEXT NULL, '
              '"email" TEXT NULL, '
              '"notes" TEXT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "parent_children" ( '
              '"parent_id" TEXT NOT NULL '
              'REFERENCES "parents"("id") ON DELETE CASCADE, '
              '"child_id" TEXT NOT NULL '
              'REFERENCES "children"("id") ON DELETE CASCADE, '
              '"is_primary" INTEGER NOT NULL DEFAULT 0, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              'PRIMARY KEY ("parent_id", "child_id")'
              ' )',
            );
            // Hot query: "who are Noah's parents?" on every child-
            // detail render. Index on child_id keeps that bounded.
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_parent_children_child" '
              'ON "parent_children" ("child_id")',
            );
          }
          if (from < 37) {
            // v37: vehicles as a first-class entity. Programs own a
            // list of named vehicles instead of re-typing make/model +
            // plate on every vehicle-check form. Standalone table with
            // no FKs into it yet — the vehicle-check form references
            // it by id in its JSON data blob, not by FK, because the
            // polymorphic-forms schema doesn't thread per-form FKs.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "vehicles" ( '
              '"id" TEXT NOT NULL PRIMARY KEY, '
              '"name" TEXT NOT NULL, '
              "\"make_model\" TEXT NOT NULL DEFAULT '', "
              "\"license_plate\" TEXT NOT NULL DEFAULT '', "
              '"notes" TEXT NULL, '
              '"created_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now')), "
              '"updated_at" INTEGER NOT NULL '
              "DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
          }
          if (from < 36) {
            // v36: entity rename "specialist" → "adult". Table names,
            // the specialist_id FK column on every related table, and
            // the idx_adult_block_specialist_day index all move to
            // "adult" naming to match the UI vocabulary. The
            // 'specialist' STRING VALUE in adult_role / role columns
            // is unchanged — that's the rotating-rover role label.
            await _runSilent(
              'ALTER TABLE "specialists" RENAME TO "adults"',
            );
            await _runSilent(
              'ALTER TABLE "specialist_availability" '
              'RENAME TO "adult_availability"',
            );
            await _runSilent(
              'ALTER TABLE "adult_availability" '
              'RENAME COLUMN "specialist_id" TO "adult_id"',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'RENAME COLUMN "specialist_id" TO "adult_id"',
            );
            await _runSilent(
              'ALTER TABLE "adult_day_blocks" '
              'RENAME COLUMN "specialist_id" TO "adult_id"',
            );
            await _runSilent(
              'ALTER TABLE "schedule_templates" '
              'RENAME COLUMN "specialist_id" TO "adult_id"',
            );
            await _runSilent(
              'ALTER TABLE "schedule_entries" '
              'RENAME COLUMN "specialist_id" TO "adult_id"',
            );
            await _runSilent(
              'DROP INDEX IF EXISTS "idx_adult_block_specialist_day"',
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_adult_block_adult_day" '
              'ON "adult_day_blocks" ("adult_id", "day_of_week")',
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
  /// Idempotently re-applies the v42 program_id stamping migration.
  /// Called from `beforeOpen` so it runs every launch — partial
  /// migrations (mid-upgrade browser close, OOM kill on native) get
  /// healed without requiring the user to wipe local data.
  ///
  /// All ALTER TABLE statements are wrapped in [_runSilent], which
  /// swallows "duplicate column" / "no such table" — so a fully-
  /// migrated DB sees this as a no-op series of failed-and-ignored
  /// statements (cheap), and a partially-migrated DB gets the
  /// missing columns filled in.
  ///
  /// Reads the table list from [kSyncedTableNames] — single source
  /// of truth shared with the cloud sync layer. Adding a synced
  /// table updates this heal automatically.
  Future<void> _healProgramIdColumns() async {
    for (final t in kSyncedTableNames) {
      await _runSilent(
        'ALTER TABLE "$t" ADD COLUMN "program_id" TEXT NULL',
      );
      await _runSilent(
        'CREATE INDEX IF NOT EXISTS '
        '"idx_${t}_program" ON "$t" ("program_id")',
      );
    }
  }

  /// One-shot data migration for the v45 schema bump. Reads any
  /// local rows from the legacy parent_concern_notes table (and
  /// its parent_concern_children join) via raw SQL — the Drift
  /// classes have already been removed from the schema, so we
  /// can't go through the type-safe API — and writes them as
  /// form_submissions rows with form_type='parent_concern'.
  ///
  /// Idempotent: insertOnConflictUpdate against the same id, so
  /// rows already migrated by the v1 app-level migration are
  /// updated in place rather than duplicated.
  ///
  /// Best-effort: if the source table doesn't exist (fresh install
  /// past v45) the SELECT raises "no such table" and _runSilent
  /// catches it. Same if any row's id is already gone — the upsert
  /// is a no-op for rows that match the existing form_submissions.
  Future<void> _migrateParentConcernRowsToFormSubmissions() async {
    try {
      final notes = await customSelect(
        'SELECT * FROM "parent_concern_notes"',
      ).get();
      if (notes.isEmpty) return;

      // Fetch all the cascade rows in one shot, then group by
      // concernId — avoids N round-trips for N notes.
      final allLinks = await customSelect(
        'SELECT * FROM "parent_concern_children"',
      ).get();
      final childIdsByConcern = <String, List<String>>{};
      for (final l in allLinks) {
        final cid = l.data['concern_id'] as String?;
        final kid = l.data['child_id'] as String?;
        if (cid == null || kid == null) continue;
        (childIdsByConcern[cid] ??= []).add(kid);
      }

      for (final note in notes) {
        final id = note.data['id'] as String?;
        if (id == null) continue;
        final childIds = childIdsByConcern[id] ?? const <String>[];
        final data = _parentConcernRowToFormData(note.data, childIds);

        // Convert epoch-second ints back to ISO timestamps for the
        // FormSubmission's date columns. The form_submissions row
        // gets its createdAt / updatedAt copied from the legacy row
        // so the Today screen's "recent activity" feed lands in the
        // same chronological position.
        final createdAt = note.data['created_at'];
        final updatedAt = note.data['updated_at'];

        // Variables list takes List<Variable<Object>>; nulls go in
        // as Variable<Object>(null). Match the engine's _toVariable
        // shape so the typing stays consistent.
        final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final variables = <Variable<Object>>[
          Variable<String>(id),
          const Variable<String>('parent_concern'),
          const Variable<String>('completed'),
          // submitted_at stamped from createdAt — these rows are
          // already-finished history.
          if (createdAt is int)
            Variable<int>(createdAt)
          else
            const Variable<Object>(null),
          const Variable<Object>(null), // author_name
          // single-child shortcut when exactly one is linked
          if (childIds.length == 1)
            Variable<String>(childIds.first)
          else
            const Variable<Object>(null),
          const Variable<Object>(null), // group_id
          const Variable<Object>(null), // trip_id
          const Variable<Object>(null), // parent_submission_id
          const Variable<Object>(null), // review_due_at
          Variable<String>(jsonEncode(data)),
          if (note.data['program_id'] is String)
            Variable<String>(note.data['program_id'] as String)
          else
            const Variable<Object>(null),
          Variable<int>(createdAt is int ? createdAt : nowEpoch),
          Variable<int>(updatedAt is int ? updatedAt : nowEpoch),
        ];
        await customInsert(
          'INSERT OR REPLACE INTO "form_submissions" '
          '("id", "form_type", "status", "submitted_at", '
          '"author_name", "child_id", "group_id", "trip_id", '
          '"parent_submission_id", "review_due_at", "data", '
          '"program_id", "created_at", "updated_at") '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          variables: variables,
        );
      }
    } on Object catch (e) {
      // "no such table" if the install is post-v45 fresh and never
      // had these tables. Other DB errors (lock contention, schema
      // drift) shouldn't block the user — log and move on; the
      // worst case is a couple of legacy rows missing from the new
      // table, which the user can re-enter manually.
      debugPrint('Parent-concern v45 migration skipped: $e');
    }
  }

  /// Maps the legacy parent_concern_notes row → the form_submissions
  /// `data` JSON shape that matches `parentConcernForm`'s field keys.
  /// Mirrors `parent_concern_migration.dart` (the deleted app-level
  /// version), kept here so the migration is self-contained inside
  /// the schema upgrade.
  Map<String, dynamic> _parentConcernRowToFormData(
    Map<String, Object?> row,
    List<String> childIds,
  ) {
    DateTime? toUtc(Object? raw) => raw is int
        ? DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true)
        : null;

    final concernDate = toUtc(row['concern_date']);
    final followUpDate = toUtc(row['follow_up_date']);
    final staffSignedAt = toUtc(row['staff_signature_date']);
    final supervisorSignedAt = toUtc(row['supervisor_signature_date']);

    final staffName = row['staff_signature'] as String?;
    final staffPath = row['staff_signature_path'] as String?;
    final supervisorName = row['supervisor_signature'] as String?;
    final supervisorPath = row['supervisor_signature_path'] as String?;

    return <String, dynamic>{
      'child_ids': childIds,
      if ((row['parent_name'] as String?)?.isNotEmpty ?? false)
        'parent_name': row['parent_name'],
      if (concernDate != null)
        'concern_date': concernDate.toIso8601String(),
      if ((row['staff_receiving'] as String?)?.isNotEmpty ?? false)
        'staff_receiving': row['staff_receiving'],
      'method_in_person': (row['method_in_person'] as int?) == 1,
      'method_phone': (row['method_phone'] as int?) == 1,
      'method_email': (row['method_email'] as int?) == 1,
      if ((row['method_other'] as String?)?.isNotEmpty ?? false)
        'method_other': row['method_other'],
      if ((row['concern_description'] as String?)?.isNotEmpty ?? false)
        'concern_description': row['concern_description'],
      if ((row['immediate_response'] as String?)?.isNotEmpty ?? false)
        'immediate_response': row['immediate_response'],
      if ((row['supervisor_notified'] as String?)?.isNotEmpty ?? false)
        'supervisor_notified': row['supervisor_notified'],
      'follow_up_monitor': (row['follow_up_monitor'] as int?) == 1,
      'follow_up_staff_check_ins':
          (row['follow_up_staff_check_ins'] as int?) == 1,
      'follow_up_supervisor_review':
          (row['follow_up_supervisor_review'] as int?) == 1,
      'follow_up_parent_conversation':
          (row['follow_up_parent_conversation'] as int?) == 1,
      if ((row['follow_up_other'] as String?)?.isNotEmpty ?? false)
        'follow_up_other': row['follow_up_other'],
      if (followUpDate != null)
        'follow_up_date': followUpDate.toIso8601String(),
      if ((row['additional_notes'] as String?)?.isNotEmpty ?? false)
        'additional_notes': row['additional_notes'],
      if (staffName != null || staffPath != null || staffSignedAt != null)
        'staff_signature': <String, dynamic>{
          'name': ?staffName,
          'signaturePath': ?staffPath,
          'signedAt': ?staffSignedAt?.toIso8601String(),
        },
      if (supervisorName != null ||
          supervisorPath != null ||
          supervisorSignedAt != null)
        'supervisor_signature': <String, dynamic>{
          'name': ?supervisorName,
          'signaturePath': ?supervisorPath,
          'signedAt': ?supervisorSignedAt?.toIso8601String(),
        },
    };
  }

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

  /// Wipes every row from every table, leaving the schema (+ indexes,
  /// FK constraints) intact. Used by the "Clear all data" danger-zone
  /// action in program settings — starts the app from a pristine state
  /// without having to reinstall.
  ///
  /// Runs with foreign keys OFF inside a transaction so the order of
  /// deletes doesn't matter — every child table would normally cascade-
  /// clean when its parent got deleted, but we want to be safe against
  /// any join shape that might protest.
  ///
  /// Callers typically pair this with `SharedPreferences.clear()` to
  /// wipe on-device UI state (mode toggles, last-expanded selections,
  /// grace windows). Attachment files on disk are left alone — they
  /// become orphans on the next DB read; the media-sweep helper can
  /// reap them separately.
  Future<void> clearAllData() async {
    await customStatement('PRAGMA foreign_keys = OFF');
    try {
      await transaction(() async {
        for (final table in allTables) {
          await customStatement('DELETE FROM "${table.actualTableName}"');
        }
      });
    } finally {
      await customStatement('PRAGMA foreign_keys = ON');
    }
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
