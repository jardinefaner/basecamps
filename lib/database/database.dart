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
    AdultRoleBlocks,
    AdultRoleBlockOverrides,
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
    MediaCache,
    MonthlyThemes,
    WeeklySubThemes,
    MonthlyActivities,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 57;

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
          await _healCurriculumArcColumns();
          await _healRoleBlockTables();
          await _healScheduleTemplateColumns();
          await _healMediaCacheTable();
          await _healAvatarEtagColumns();
          await _healV52QolColumns();
          await _healV53AudienceAgeColumn();
          await _healV54AuthUserIdColumn();
          // v55+v56 table creation must happen BEFORE the dirty-
          // fields heal, otherwise the ALTER TABLE on those new
          // tables silently fails (table doesn't exist yet) and
          // their dirty_fields column never gets added — which
          // then breaks the sync engine's partial-UPDATE pushes.
          await _healV55MonthlyPlanTables();
          await _healV56MonthlyActivitiesTable();
          await _healV57MonthlyActivitySpanColumns();
          await _healDirtyFieldsColumns();
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
          if (from < 57) {
            // v57: monthly plan multi-day spans (Slice 3). Adds
            // span_id + span_position to monthly_activities so
            // multiple rows can be stitched into a single logical
            // activity that runs across N consecutive days. Cloud
            // parity: migration 0034.
            await _runSilent(
              'ALTER TABLE "monthly_activities" '
              'ADD COLUMN "span_id" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "monthly_activities" '
              'ADD COLUMN "span_position" INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (from < 56) {
            // v56: monthly plan activities (Slice 2). One row per
            // variant; (program, group, date, position) addresses a
            // variant within its cell. Cloud parity: migration 0033.
            await m.createTable(monthlyActivities);
          }
          if (from < 55) {
            // v55: monthly plan persistence (Slice 1). Two new
            // tables: monthly_themes (one row per program/month)
            // and weekly_subthemes (one row per program/Monday).
            // Cloud parity: migration 0032. The schema-heal below
            // (`_healV55MonthlyPlanTables`) defends against
            // partial-upgrade states by re-running CREATE TABLE
            // IF NOT EXISTS on every launch.
            await m.createTable(monthlyThemes);
            await m.createTable(weeklySubThemes);
          }
          if (from < 54) {
            // v54: adults.auth_user_id — identity binding. The
            // Supabase auth user id (uuid as text) of the signed-in
            // account that *is* this adult. Stamped by the
            // accept-invite edge function when the recipient
            // redeems an invite carrying an `adult_id`. Cloud
            // parity: migration 0030.
            await _runSilent(
              'ALTER TABLE "adults" ADD COLUMN "auth_user_id" TEXT NULL',
            );
          }
          if (from < 53) {
            // v53: groups.audience_age_label — free-text age range
            // attached to each group. Drives AI generation context
            // and could later filter activity-library picks. Cloud
            // parity: migration 0029.
            await _runSilent(
              'ALTER TABLE "groups" ADD COLUMN "audience_age_label" TEXT NULL',
            );
          }
          if (from < 52) {
            // v52: schema cleanup + QoL columns. All additive
            // nullable — existing rows are unaffected.
            //
            // Cloud parity: cloud migrations 0027 + 0028 add the
            // mirrors. Sync engine pushes/pulls these columns
            // through the same generic path as everything else
            // — the new columns travel with each row's
            // upsert/UPDATE.
            //
            // archived_at: hide-but-keep on people / asset
            // tables. Pickers will filter `archived_at IS NULL`
            // once the UI ships.
            //
            // position: user-orderable lists. NULL falls back
            // to alpha-by-name in repos that wire up the sort.
            //
            // created_by: audit "who logged this" — populated
            // by repos from `currentSessionProvider.user.id`
            // on insert; older rows keep the legacy free-text
            // author_name fallback.
            //
            // display_name: members card pretty name. Bootstrap
            // populates from auth.users metadata on every
            // membership upsert.
            for (final t in const [
              'groups',
              'rooms',
              'roles',
              'children',
              'adults',
              'parents',
              'vehicles',
            ]) {
              await _runSilent(
                'ALTER TABLE "$t" ADD COLUMN "archived_at" INTEGER NULL',
              );
            }
            for (final t in const ['groups', 'rooms', 'roles', 'children']) {
              await _runSilent(
                'ALTER TABLE "$t" ADD COLUMN "position" INTEGER NULL',
              );
            }
            await _runSilent(
              'ALTER TABLE "observations" ADD COLUMN "created_by" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "form_submissions" ADD COLUMN "created_by" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "program_members" ADD COLUMN "display_name" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "parent_children" ADD COLUMN "updated_at" INTEGER NULL',
            );
            // adult_role normalization. Cloud already migrates
            // 'adult' → 'specialist' in 0027; mirror locally so
            // a device that hasn't pulled cloud yet doesn't
            // round-trip the legacy value back.
            await _runSilent(
              "UPDATE \"adults\" SET \"adult_role\" = 'specialist' "
              "WHERE \"adult_role\" = 'adult'",
            );
          }
          if (from < 51) {
            // v51: per-upload content tag for avatars. The bucket
            // key is stable per row id, so without an etag a
            // re-uploaded photo is invisible to other devices'
            // caches — they'd serve stale bytes forever. Adding
            // a nullable column is additive; existing rows have
            // null etag and the resolver treats null-vs-null as
            // a match, so legacy avatars stay valid until the
            // owner re-picks (at which point the etag pops in
            // and invalidation kicks in everywhere).
            //
            // Three columns total — both entity tables get an
            // `avatar_etag`, plus `media_cache.etag` so the
            // cache row remembers which version of bytes it
            // holds.
            await _runSilent(
              'ALTER TABLE "adults" ADD COLUMN "avatar_etag" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "children" ADD COLUMN "avatar_etag" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "media_cache" ADD COLUMN "etag" TEXT NULL',
            );
          }
          if (from < 50) {
            // v50: local-only `media_cache` blob table. Keyed by
            // bucket-relative `storage_path`; bytes are downloaded
            // once from Supabase Storage and reused thereafter.
            // Web especially benefits — no filesystem means every
            // signed-URL fetch was previously re-downloading bytes
            // on every page reload. CREATE IF NOT EXISTS so a
            // partial-migration recovery is harmless.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "media_cache" ('
              ' "storage_path" TEXT NOT NULL PRIMARY KEY, '
              ' "bytes" BLOB NOT NULL, '
              ' "content_type" TEXT NULL, '
              ' "cached_at" INTEGER NOT NULL '
              "   DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
          }
          if (from < 49) {
            // v49: field-level dirty tracking. Each entity table
            // gets a `dirty_fields` TEXT column (a JSON array of
            // column names that have un-pushed local edits). The
            // sync engine uses this to do partial UPDATEs (only
            // dirty fields go to cloud) instead of full-row
            // upserts — eliminating the "two devices edit
            // different fields, last writer overwrites" data
            // loss. Local-only column; never pushed, never
            // pulled. See [_healDirtyFieldsColumns] for details.
            for (final t in kSyncedTableNames) {
              await _runSilent(
                'ALTER TABLE "$t" ADD COLUMN "dirty_fields" TEXT NULL',
              );
            }
          }
          if (from < 48) {
            // v48: per-adult role timeline tables. Patterns
            // (`adult_role_blocks`) plus date-specific overrides
            // (`adult_role_block_overrides`) so a teacher's
            // anchor → specialist → break flow is editable
            // both as a recurring weekday plan and as one-off
            // adjustments for substitutes / special days.
            //
            // No data migration — adds two empty tables. The
            // existing `adult_day_blocks` table stays for its
            // current callers (breaks/lunches feature). Future
            // work can reconcile the two if needed; for now
            // they coexist with non-overlapping semantics.
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "adult_role_blocks" ('
              ' "id" TEXT NOT NULL PRIMARY KEY, '
              ' "adult_id" TEXT NOT NULL '
              '   REFERENCES "adults"("id") ON DELETE CASCADE, '
              ' "weekday" INTEGER NOT NULL, '
              ' "start_minute" INTEGER NOT NULL, '
              ' "end_minute" INTEGER NOT NULL, '
              ' "kind" TEXT NOT NULL, '
              ' "subject" TEXT NULL, '
              ' "group_id" TEXT NULL '
              '   REFERENCES "groups"("id") ON DELETE SET NULL, '
              ' "program_id" TEXT NULL, '
              ' "created_at" INTEGER NOT NULL '
              "   DEFAULT (strftime('%s', 'now')), "
              ' "updated_at" INTEGER NOT NULL '
              "   DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_adult_role_blocks_adult" '
              'ON "adult_role_blocks" ("adult_id", "weekday")',
            );
            await _runSilent(
              'CREATE TABLE IF NOT EXISTS "adult_role_block_overrides" ('
              ' "id" TEXT NOT NULL PRIMARY KEY, '
              ' "adult_id" TEXT NOT NULL '
              '   REFERENCES "adults"("id") ON DELETE CASCADE, '
              ' "date" INTEGER NOT NULL, '
              ' "start_minute" INTEGER NOT NULL, '
              ' "end_minute" INTEGER NOT NULL, '
              ' "kind" TEXT NOT NULL, '
              ' "subject" TEXT NULL, '
              ' "group_id" TEXT NULL '
              '   REFERENCES "groups"("id") ON DELETE SET NULL, '
              ' "replaces" INTEGER NOT NULL DEFAULT 0, '
              ' "program_id" TEXT NULL, '
              ' "created_at" INTEGER NOT NULL '
              "   DEFAULT (strftime('%s', 'now')), "
              ' "updated_at" INTEGER NOT NULL '
              "   DEFAULT (strftime('%s', 'now'))"
              ' )',
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_adult_role_block_overrides_adult_date" '
              'ON "adult_role_block_overrides" ("adult_id", "date")',
            );
          }
          if (from < 47) {
            // v47: curriculum phase + per-week color + engine
            // notes on lesson_sequences. All additive nullable
            // columns. Lets the curriculum view group weeks by
            // phase (e.g. "ALL ABOUT ME" spans weeks 1–2),
            // accent each week with its own color (gradient
            // within a phase), and surface a behind-the-scenes
            // note pane for the curriculum author. Mirrors the
            // cloud migration in 0013_curriculum_phases.sql.
            await _runSilent(
              'ALTER TABLE "lesson_sequences" '
              'ADD COLUMN "phase" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "lesson_sequences" '
              'ADD COLUMN "color_hex" TEXT NULL',
            );
            await _runSilent(
              'ALTER TABLE "lesson_sequences" '
              'ADD COLUMN "engine_notes" TEXT NULL',
            );
          }
          if (from < 46) {
            // v46: curriculum arc — wire LessonSequences to a Theme,
            // give each sequence a "core question" prompt for the
            // morning meeting / weekly recap, and stamp every
            // LessonSequenceItem with a day-of-week + a `kind`
            // discriminator (daily ritual vs weekly milestone).
            //
            // Also add an `age_variants` JSON blob to ActivityLibrary
            // so a single card can carry adjacent-age rewrites of its
            // summary / key points / learning goals — the renderer
            // toggles between them when the curriculum view's "show
            // age scaling" switch is on.
            //
            // All additive nullable columns (plus a defaulted text on
            // `kind`), so existing rows keep working unchanged. The
            // schema-heal in beforeOpen re-applies these every launch
            // for users whose mid-upgrade IndexedDB closed before the
            // ALTER finished.
            await _runSilent(
              'ALTER TABLE "lesson_sequences" '
              'ADD COLUMN "theme_id" TEXT NULL '
              'REFERENCES "themes"("id") ON DELETE SET NULL',
            );
            await _runSilent(
              'ALTER TABLE "lesson_sequences" '
              'ADD COLUMN "core_question" TEXT NULL',
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_lesson_sequences_theme" '
              'ON "lesson_sequences" ("theme_id")',
            );
            await _runSilent(
              'ALTER TABLE "lesson_sequence_items" '
              'ADD COLUMN "day_of_week" INTEGER NULL',
            );
            await _runSilent(
              'ALTER TABLE "lesson_sequence_items" '
              "ADD COLUMN \"kind\" TEXT NOT NULL DEFAULT 'daily'",
            );
            await _runSilent(
              'CREATE INDEX IF NOT EXISTS '
              '"idx_lesson_sequence_items_kind" '
              'ON "lesson_sequence_items" ("sequence_id", "kind")',
            );
            await _runSilent(
              'ALTER TABLE "activity_library" '
              'ADD COLUMN "age_variants" TEXT NULL',
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

  /// Re-apply the v46 curriculum-arc additive ALTERs every launch.
  /// Same logic as [_healProgramIdColumns]: cheap (no-ops once the
  /// columns exist), defends against partial-upgrade IndexedDB
  /// states. Without this, a sequence-edit screen on a half-migrated
  /// DB would fail with "no such column: theme_id" the first time
  /// the user touches the curriculum view.
  Future<void> _healCurriculumArcColumns() async {
    await _runSilent(
      'ALTER TABLE "lesson_sequences" '
      'ADD COLUMN "theme_id" TEXT NULL '
      'REFERENCES "themes"("id") ON DELETE SET NULL',
    );
    await _runSilent(
      'ALTER TABLE "lesson_sequences" '
      'ADD COLUMN "core_question" TEXT NULL',
    );
    await _runSilent(
      'CREATE INDEX IF NOT EXISTS '
      '"idx_lesson_sequences_theme" '
      'ON "lesson_sequences" ("theme_id")',
    );
    await _runSilent(
      'ALTER TABLE "lesson_sequence_items" '
      'ADD COLUMN "day_of_week" INTEGER NULL',
    );
    await _runSilent(
      'ALTER TABLE "lesson_sequence_items" '
      "ADD COLUMN \"kind\" TEXT NOT NULL DEFAULT 'daily'",
    );
    await _runSilent(
      'CREATE INDEX IF NOT EXISTS '
      '"idx_lesson_sequence_items_kind" '
      'ON "lesson_sequence_items" ("sequence_id", "kind")',
    );
    await _runSilent(
      'ALTER TABLE "activity_library" '
      'ADD COLUMN "age_variants" TEXT NULL',
    );
    // v47 columns — phase / color / engine notes per week.
    await _runSilent(
      'ALTER TABLE "lesson_sequences" '
      'ADD COLUMN "phase" TEXT NULL',
    );
    await _runSilent(
      'ALTER TABLE "lesson_sequences" '
      'ADD COLUMN "color_hex" TEXT NULL',
    );
    await _runSilent(
      'ALTER TABLE "lesson_sequences" '
      'ADD COLUMN "engine_notes" TEXT NULL',
    );
  }

  /// Re-apply the v48 role-block CREATE TABLE statements every
  /// launch. Same logic as the other heal helpers: idempotent
  /// (CREATE TABLE IF NOT EXISTS short-circuits cleanly), defends
  /// against partial-upgrade IndexedDB states on web where the
  /// migration could close mid-run.
  Future<void> _healRoleBlockTables() async {
    await _runSilent(
      'CREATE TABLE IF NOT EXISTS "adult_role_blocks" ('
      ' "id" TEXT NOT NULL PRIMARY KEY, '
      ' "adult_id" TEXT NOT NULL '
      '   REFERENCES "adults"("id") ON DELETE CASCADE, '
      ' "weekday" INTEGER NOT NULL, '
      ' "start_minute" INTEGER NOT NULL, '
      ' "end_minute" INTEGER NOT NULL, '
      ' "kind" TEXT NOT NULL, '
      ' "subject" TEXT NULL, '
      ' "group_id" TEXT NULL '
      '   REFERENCES "groups"("id") ON DELETE SET NULL, '
      ' "program_id" TEXT NULL, '
      ' "created_at" INTEGER NOT NULL '
      "   DEFAULT (strftime('%s', 'now')), "
      ' "updated_at" INTEGER NOT NULL '
      "   DEFAULT (strftime('%s', 'now'))"
      ' )',
    );
    await _runSilent(
      'CREATE INDEX IF NOT EXISTS '
      '"idx_adult_role_blocks_adult" '
      'ON "adult_role_blocks" ("adult_id", "weekday")',
    );
    await _runSilent(
      'CREATE TABLE IF NOT EXISTS "adult_role_block_overrides" ('
      ' "id" TEXT NOT NULL PRIMARY KEY, '
      ' "adult_id" TEXT NOT NULL '
      '   REFERENCES "adults"("id") ON DELETE CASCADE, '
      ' "date" INTEGER NOT NULL, '
      ' "start_minute" INTEGER NOT NULL, '
      ' "end_minute" INTEGER NOT NULL, '
      ' "kind" TEXT NOT NULL, '
      ' "subject" TEXT NULL, '
      ' "group_id" TEXT NULL '
      '   REFERENCES "groups"("id") ON DELETE SET NULL, '
      ' "replaces" INTEGER NOT NULL DEFAULT 0, '
      ' "program_id" TEXT NULL, '
      ' "created_at" INTEGER NOT NULL '
      "   DEFAULT (strftime('%s', 'now')), "
      ' "updated_at" INTEGER NOT NULL '
      "   DEFAULT (strftime('%s', 'now'))"
      ' )',
    );
    await _runSilent(
      'CREATE INDEX IF NOT EXISTS '
      '"idx_adult_role_block_overrides_adult_date" '
      'ON "adult_role_block_overrides" ("adult_id", "date")',
    );
  }

  /// Re-apply the v49 `dirty_fields` ALTER for every entity table
  /// every launch. Same pattern as the other heal helpers — cheap
  /// (the ALTER no-ops once the column exists, swallowed by
  /// _runSilent), defends against partial-upgrade DBs.
  ///
  /// `dirty_fields` is a JSON-encoded `List<String>` of column
  /// names that have un-pushed local edits. Local-only column;
  /// never pushed to cloud, never read from cloud. The sync
  /// engine reads it on push to construct partial UPDATEs (only
  /// the dirty fields go to cloud), and on pull to preserve
  /// dirty fields across cloud-row merges.
  Future<void> _healDirtyFieldsColumns() async {
    for (final t in kSyncedTableNames) {
      await _runSilent(
        'ALTER TABLE "$t" ADD COLUMN "dirty_fields" TEXT NULL',
      );
    }
  }

  /// Re-apply the v50 `media_cache` CREATE TABLE every launch.
  /// Web IndexedDB has historically been the worst offender for
  /// half-applied schema upgrades (tab closed mid-migration, app
  /// killed during launch), and a missing `media_cache` table
  /// silently breaks every avatar render — `ensureBytes` throws
  /// on the cache lookup, the FutureProvider emits AsyncError,
  /// and the widget shows the fallback initial with no diagnostic.
  /// CREATE TABLE IF NOT EXISTS is a cheap no-op when the table
  /// already exists, so we run it on every launch like the
  /// column heals.
  Future<void> _healMediaCacheTable() async {
    await _runSilent(
      'CREATE TABLE IF NOT EXISTS "media_cache" ('
      ' "storage_path" TEXT NOT NULL PRIMARY KEY, '
      ' "bytes" BLOB NOT NULL, '
      ' "content_type" TEXT NULL, '
      ' "etag" TEXT NULL, '
      ' "cached_at" INTEGER NOT NULL '
      "   DEFAULT (strftime('%s', 'now'))"
      ' )',
    );
  }

  /// Re-apply the v51 `avatar_etag` ALTER on the two avatar-bearing
  /// entity tables + the `etag` column on `media_cache` every
  /// launch. Same defensive pattern as [_healDirtyFieldsColumns]:
  /// cheap, no-ops once the columns exist, and rescues users
  /// whose initial v51 upgrade landed only partially (web
  /// IndexedDB closed mid-write, app killed during launch).
  Future<void> _healAvatarEtagColumns() async {
    await _runSilent(
      'ALTER TABLE "adults" ADD COLUMN "avatar_etag" TEXT NULL',
    );
    await _runSilent(
      'ALTER TABLE "children" ADD COLUMN "avatar_etag" TEXT NULL',
    );
    await _runSilent(
      'ALTER TABLE "media_cache" ADD COLUMN "etag" TEXT NULL',
    );
  }

  /// Re-apply v52 QoL ALTERs every launch. Same defensive pattern
  /// as the other heals — cheap, no-ops on the second run, and
  /// rescues users whose v52 upgrade landed only partially.
  Future<void> _healV52QolColumns() async {
    for (final t in const [
      'groups',
      'rooms',
      'roles',
      'children',
      'adults',
      'parents',
      'vehicles',
    ]) {
      await _runSilent(
        'ALTER TABLE "$t" ADD COLUMN "archived_at" INTEGER NULL',
      );
    }
    for (final t in const ['groups', 'rooms', 'roles', 'children']) {
      await _runSilent(
        'ALTER TABLE "$t" ADD COLUMN "position" INTEGER NULL',
      );
    }
    await _runSilent(
      'ALTER TABLE "observations" ADD COLUMN "created_by" TEXT NULL',
    );
    await _runSilent(
      'ALTER TABLE "form_submissions" ADD COLUMN "created_by" TEXT NULL',
    );
    await _runSilent(
      'ALTER TABLE "program_members" ADD COLUMN "display_name" TEXT NULL',
    );
    await _runSilent(
      'ALTER TABLE "parent_children" ADD COLUMN "updated_at" INTEGER NULL',
    );
  }

  /// Re-apply v53's groups.audience_age_label ALTER every launch.
  /// Same defensive pattern as the other heals — no-op on second
  /// run, rescues users whose v53 upgrade landed only partially.
  Future<void> _healV53AudienceAgeColumn() async {
    await _runSilent(
      'ALTER TABLE "groups" ADD COLUMN "audience_age_label" TEXT NULL',
    );
  }

  /// Re-apply v54's adults.auth_user_id ALTER every launch.
  Future<void> _healV54AuthUserIdColumn() async {
    await _runSilent(
      'ALTER TABLE "adults" ADD COLUMN "auth_user_id" TEXT NULL',
    );
  }

  /// v55 schema heal. Re-creates the monthly_themes + weekly_subthemes
  /// tables on every launch as a safety net against partial upgrades
  /// (web IndexedDB closed mid-migration, native app force-killed
  /// during launch). CREATE TABLE IF NOT EXISTS is a no-op when the
  /// tables already exist; if they're missing — or if a partial
  /// upgrade left them only half-formed — this brings them up to
  /// the full v55 shape so subsequent inserts don't blow up with
  /// "no such table" errors.
  Future<void> _healV55MonthlyPlanTables() async {
    await _runSilent(
      'CREATE TABLE IF NOT EXISTS "monthly_themes" '
      '("id" TEXT NOT NULL, '
      '"program_id" TEXT NULL, '
      '"year_month" TEXT NOT NULL, '
      '"theme" TEXT NULL, '
      '"created_at" INTEGER NOT NULL, '
      '"updated_at" INTEGER NOT NULL, '
      '"deleted_at" INTEGER NULL, '
      'PRIMARY KEY ("id"))',
    );
    await _runSilent(
      'CREATE TABLE IF NOT EXISTS "weekly_subthemes" '
      '("id" TEXT NOT NULL, '
      '"program_id" TEXT NULL, '
      '"monday_date" TEXT NOT NULL, '
      '"sub_theme" TEXT NULL, '
      '"created_at" INTEGER NOT NULL, '
      '"updated_at" INTEGER NOT NULL, '
      '"deleted_at" INTEGER NULL, '
      'PRIMARY KEY ("id"))',
    );
  }

  /// v56 schema heal — same belt-and-suspenders pattern as v55.
  /// Re-runs CREATE TABLE IF NOT EXISTS on every launch so a
  /// partial upgrade (e.g. web IDB closed mid-migration) doesn't
  /// leave the user without the activities table.
  Future<void> _healV56MonthlyActivitiesTable() async {
    await _runSilent(
      'CREATE TABLE IF NOT EXISTS "monthly_activities" '
      '("id" TEXT NOT NULL, '
      '"program_id" TEXT NULL, '
      '"group_id" TEXT NOT NULL, '
      '"date" TEXT NOT NULL, '
      '"position" INTEGER NOT NULL DEFAULT 0, '
      '"title" TEXT NULL, '
      '"description" TEXT NULL, '
      '"objectives" TEXT NULL, '
      '"steps" TEXT NULL, '
      '"materials" TEXT NULL, '
      '"link" TEXT NULL, '
      '"created_at" INTEGER NOT NULL, '
      '"updated_at" INTEGER NOT NULL, '
      '"deleted_at" INTEGER NULL, '
      'PRIMARY KEY ("id"))',
    );
  }

  /// v57 schema heal — add span_id + span_position to
  /// monthly_activities. ALTER COLUMN ADD IF NOT EXISTS isn't
  /// supported by older SQLite; _runSilent swallows the
  /// "duplicate column" error from re-running the ALTER.
  Future<void> _healV57MonthlyActivitySpanColumns() async {
    await _runSilent(
      'ALTER TABLE "monthly_activities" '
      'ADD COLUMN "span_id" TEXT NULL',
    );
    await _runSilent(
      'ALTER TABLE "monthly_activities" '
      'ADD COLUMN "span_position" INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// Mark [fields] as dirty on the row [id] in [table]. Merges
  /// with any existing dirty list (so consecutive edits before a
  /// push accumulate). Called by repository update methods after
  /// they write the row's column changes.
  ///
  /// JSON-encoded `List<String>`; null means clean. Cheap: one
  /// SELECT + one UPDATE per call. The sync engine's push reads
  /// this to construct a partial UPDATE; the engine's pull merge
  /// reads it to know which fields to preserve.
  Future<void> markDirty(
    String table,
    String id,
    List<String> fields,
  ) async {
    if (fields.isEmpty) return;
    final existing = await customSelect(
      'SELECT "dirty_fields" FROM "$table" WHERE id = ?',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();
    final current = <String>{};
    final raw = existing?.data['dirty_fields'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final v in decoded) {
            if (v is String) current.add(v);
          }
        }
      } on FormatException {
        // Tolerate corrupt JSON — start fresh.
      }
    }
    current.addAll(fields);
    final encoded = jsonEncode(current.toList()..sort());
    await customUpdate(
      'UPDATE "$table" SET "dirty_fields" = ? WHERE id = ?',
      variables: [Variable<String>(encoded), Variable<String>(id)],
      updates: {},
      updateKind: UpdateKind.update,
    );
  }

  /// Read the current dirty-field list for a row. Returns an
  /// empty list when the row is clean (column null or empty
  /// JSON). Used by the sync engine's push path to construct
  /// the partial UPDATE.
  Future<List<String>> readDirtyFields(String table, String id) async {
    final row = await customSelect(
      'SELECT "dirty_fields" FROM "$table" WHERE id = ?',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();
    if (row == null) return const [];
    final raw = row.data['dirty_fields'];
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final v in decoded) if (v is String) v];
    } on FormatException {
      return const [];
    }
  }

  /// Clear the dirty-field list after a successful push. Sets
  /// the column back to NULL. Called by the sync engine on
  /// successful upsert / partial-update completion.
  Future<void> clearDirtyFields(String table, String id) async {
    await customUpdate(
      'UPDATE "$table" SET "dirty_fields" = NULL WHERE id = ?',
      variables: [Variable<String>(id)],
      updates: {},
      updateKind: UpdateKind.update,
    );
  }

  /// Re-apply additive ALTERs on `schedule_templates` every launch.
  /// A teacher's phone hit:
  ///
  ///   SqliteException: table schedule_templates has no column
  ///   named adult_name
  ///
  /// when the sync engine tried to upsert a cloud row carrying
  /// `adult_name`. The column exists in the Drift @DataClass and
  /// in cloud rows, but their device was created at a schema
  /// version that didn't have it and no `onUpgrade` block ever
  /// added it. The pull transaction rolled back; schedule_templates
  /// stopped syncing entirely on that device.
  ///
  /// Same idiom as [_healProgramIdColumns] / [_healCurriculumArcColumns]:
  /// idempotent ALTERs that no-op once the column exists. Cheap on
  /// healthy DBs, lifesaver on partial-upgrade ones.
  Future<void> _healScheduleTemplateColumns() async {
    await _runSilent(
      'ALTER TABLE "schedule_templates" '
      'ADD COLUMN "adult_name" TEXT NULL',
    );
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

  /// Wipe every program-scoped row + cascades for [programId] from
  /// the local DB. Used on sign-out, on leave-program, and on
  /// delete-program so stale rows from a no-longer-active program
  /// don't linger and surface in detail screens / search results.
  ///
  /// Drift's onDelete: CASCADE on the foreign keys handles the
  /// child rows (parent_children, observation_children,
  /// trip_groups, etc.) automatically when we delete the parent
  /// entity rows. The few entity tables that have program_id
  /// directly (the kSyncedTableNames list) are scrubbed first.
  /// Programs + program_members rows for this id are also wiped
  /// so the active-membership lookup doesn't keep finding them.
  /// Finally we drop the sync_state watermark so a re-join
  /// re-pulls cleanly instead of resuming a stale watermark.
  Future<void> wipeProgramData(String programId) async {
    await customStatement('PRAGMA foreign_keys = ON');
    await transaction(() async {
      for (final t in kSyncedTableNames) {
        try {
          await customUpdate(
            'DELETE FROM "$t" WHERE "program_id" = ?',
            variables: [Variable<String>(programId)],
          );
        } on Object {
          // Schema drift / missing column — skip; another table
          // will still be wiped.
        }
      }
      try {
        await customUpdate(
          'DELETE FROM "program_members" WHERE "program_id" = ?',
          variables: [Variable<String>(programId)],
        );
      } on Object {
        // Membership table absent (shouldn't happen post-v41).
      }
      try {
        await customUpdate(
          'DELETE FROM "programs" WHERE "id" = ?',
          variables: [Variable<String>(programId)],
        );
      } on Object {
        // Programs table absent (shouldn't happen post-v41).
      }
      try {
        await customUpdate(
          'DELETE FROM "sync_state" WHERE "program_id" = ?',
          variables: [Variable<String>(programId)],
        );
      } on Object {
        // sync_state pre-v43 doesn't exist; harmless skip.
      }
    });
  }

  /// Wipe every program's data — used on full sign-out so the
  /// next sign-in (potentially as a different user) doesn't
  /// inherit the previous user's local rows.
  Future<void> wipeAllProgramData() async {
    final ids = await select(programs).get();
    for (final p in ids) {
      await wipeProgramData(p.id);
    }
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
