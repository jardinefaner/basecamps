import 'package:basecamp/features/sync/sync_engine.dart';

/// Every program-scoped table that participates in sync, declared
/// in one place. Adding a new table = add a const here + run the
/// matching cloud SQL migration. The engine handles the rest.
///
/// Each spec lists:
///   - the SQL table name (must match between Drift + cloud)
///   - the date-typed columns (need ISO ↔ unix-seconds translation)
///   - cascade tables that follow the parent through sync
///
/// Order of definitions matches the cloud migration's order to
/// keep mental mapping easy. Pull-on-launch iterates in
/// `kAllSpecs` order so FK targets land before dependents.

const groupsSpec = TableSpec(
  table: 'groups',
  dateColumns: {'created_at', 'updated_at'},
);

const roomsSpec = TableSpec(
  table: 'rooms',
  dateColumns: {'created_at', 'updated_at'},
);

const rolesSpec = TableSpec(
  table: 'roles',
  dateColumns: {'created_at', 'updated_at'},
);

const parentsSpec = TableSpec(
  table: 'parents',
  dateColumns: {'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(
      table: 'parent_children',
      parentColumn: 'parent_id',
      dateColumns: {'created_at'},
    ),
  ],
);

const childrenSpec = TableSpec(
  table: 'children',
  dateColumns: {'birth_date', 'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(
      table: 'child_schedule_overrides',
      parentColumn: 'child_id',
      dateColumns: {'date', 'created_at', 'updated_at'},
    ),
    CascadeSpec(
      table: 'attendance',
      parentColumn: 'child_id',
      // `date` is the only event-bearing DateTime; clock_time
      // and pickup_time are "HH:mm" text strings (round-trip
      // without conversion). created_at/updated_at are audit
      // columns Drift adds.
      dateColumns: {'date', 'created_at', 'updated_at'},
    ),
  ],
);

const adultsSpec = TableSpec(
  table: 'adults',
  dateColumns: {'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(
      table: 'adult_availability',
      parentColumn: 'adult_id',
      dateColumns: {'start_date', 'end_date', 'created_at', 'updated_at'},
    ),
    CascadeSpec(
      table: 'adult_day_blocks',
      parentColumn: 'adult_id',
      // No `date` column on this table in either Drift
      // (lib/database/tables.dart) or cloud (0005); audit caught
      // the typo before it could matter, but if a future column
      // ever lands with that name the spec would silently mistype
      // it. Just the audit columns.
      dateColumns: {'created_at', 'updated_at'},
    ),
    // v48: classroom-rotation timeline. Pattern + per-date
    // overrides ride along with the parent adult on every push.
    CascadeSpec(
      table: 'adult_role_blocks',
      parentColumn: 'adult_id',
      dateColumns: {'created_at', 'updated_at'},
    ),
    CascadeSpec(
      table: 'adult_role_block_overrides',
      parentColumn: 'adult_id',
      dateColumns: {'date', 'created_at', 'updated_at'},
    ),
  ],
);

const vehiclesSpec = TableSpec(
  table: 'vehicles',
  dateColumns: {'created_at', 'updated_at'},
);

const tripsSpec = TableSpec(
  table: 'trips',
  dateColumns: {'date', 'end_date', 'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(table: 'trip_groups', parentColumn: 'trip_id'),
  ],
);

const activityLibrarySpec = TableSpec(
  table: 'activity_library',
  dateColumns: {'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(
      table: 'activity_library_domain_tags',
      parentColumn: 'library_item_id',
    ),
    CascadeSpec(
      table: 'activity_library_usages',
      parentColumn: 'library_item_id',
      dateColumns: {'used_on', 'created_at'},
    ),
  ],
);

const lessonSequencesSpec = TableSpec(
  table: 'lesson_sequences',
  dateColumns: {'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(
      table: 'lesson_sequence_items',
      parentColumn: 'sequence_id',
      dateColumns: {'created_at'},
    ),
  ],
);

const themesSpec = TableSpec(
  table: 'themes',
  dateColumns: {'start_date', 'end_date', 'created_at', 'updated_at'},
);

const scheduleTemplatesSpec = TableSpec(
  table: 'schedule_templates',
  dateColumns: {'start_date', 'end_date', 'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(table: 'template_groups', parentColumn: 'template_id'),
  ],
);

const scheduleEntriesSpec = TableSpec(
  table: 'schedule_entries',
  dateColumns: {'date', 'end_date', 'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(table: 'entry_groups', parentColumn: 'entry_id'),
  ],
);

const observationsSpec = TableSpec(
  table: 'observations',
  dateColumns: {'activity_date', 'created_at', 'updated_at'},
  cascades: [
    CascadeSpec(
      table: 'observation_children',
      parentColumn: 'observation_id',
      dateColumns: {'created_at'},
    ),
    CascadeSpec(
      table: 'observation_domain_tags',
      parentColumn: 'observation_id',
    ),
    CascadeSpec(
      table: 'observation_attachments',
      parentColumn: 'observation_id',
      dateColumns: {'created_at'},
    ),
  ],
);

// parentConcernNotesSpec — REMOVED in v45 (the table was dropped
// after migrating its rows into form_submissions). The polymorphic
// form's data syncs through formSubmissionsSpec like every other
// form type.

const formSubmissionsSpec = TableSpec(
  table: 'form_submissions',
  dateColumns: {'submitted_at', 'review_due_at', 'created_at', 'updated_at'},
);

/// Every spec, organized into FK-ordered tiers. Each tier may pull
/// in parallel (no FKs between siblings); tiers run sequentially so
/// FK targets land before dependents. Bootstrap and Sync Now both
/// honor this — the engine's pull is parallel within a tier and
/// awaited between tiers.
///
/// To add a new table: define a const TableSpec above, add it to
/// the right tier here, and add the matching cloud SQL migration.
/// Nothing else updates — the schema-heal, the backfill, and the
/// pull bootstrap all read from this list.
const List<List<TableSpec>> kSpecTiers = [
  // Tier 1 — true foundation. No FKs to ANY other entity table.
  [
    groupsSpec,
    rolesSpec,
    vehiclesSpec,
    themesSpec,
  ],
  // Tier 2 — references tier-1 entities. Rooms moved here from
  // tier 1 because of its `default_for_group_id` FK to groups —
  // pulling rooms in parallel with groups raced and dropped the
  // room rows when groups hadn't landed yet.
  [
    parentsSpec,
    childrenSpec,
    adultsSpec,
    roomsSpec,
    activityLibrarySpec,
    lessonSequencesSpec,
  ],
  // Tier 3 — events + forms. Reference tier-1/tier-2 entities.
  [
    scheduleTemplatesSpec,
    tripsSpec,
    scheduleEntriesSpec,
    observationsSpec,
    formSubmissionsSpec,
  ],
];

/// Specs whose **cascade tables** have FKs into tiers later than
/// the parent's own tier — e.g. `activity_library_usages` is a
/// cascade of tier-2 `activity_library` but holds nullable FKs to
/// `schedule_templates.id` (tier 3). Pulling the cascade together
/// with the parent fails because the FK targets aren't loaded yet.
///
/// The bootstrap solution: after every tier has pulled, do a
/// second pass that re-fires the cascades for these specs only —
/// by that point the FK targets exist locally and the inserts go
/// through cleanly.
const List<TableSpec> kPostTierCascadeRefreshSpecs = [
  activityLibrarySpec,
];

/// Flat view of every spec in tier order. Use [kSpecTiers] when
/// you care about FK ordering (pull, parallel batching); use this
/// when you just want to iterate every synced table (schema-heal,
/// backfill, cloud-table SQL generation).
List<TableSpec> get kAllSpecs => [
      for (final tier in kSpecTiers) ...tier,
    ];

/// Just the SQL table names. Used by:
///   - Drift's `_healProgramIdColumns` (re-run the v42 ALTER for
///     each)
///   - ProgramsRepository.backfillUntaggedRows (UPDATE program_id
///     for each)
///   - cross-references in cloud SQL comments
///
/// Single source of truth: change this list (via the specs above)
/// and every consumer updates in lockstep.
List<String> get kAllSyncedTableNames =>
    [for (final s in kAllSpecs) s.table];
