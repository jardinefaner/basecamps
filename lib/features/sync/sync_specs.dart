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

const parentConcernNotesSpec = TableSpec(
  table: 'parent_concern_notes',
  dateColumns: {
    'concern_date',
    'follow_up_date',
    'staff_signature_date',
    'supervisor_signature_date',
    'created_at',
    'updated_at',
  },
  cascades: [
    CascadeSpec(
      table: 'parent_concern_children',
      // Drift column is `concern_id` (the snake_case mapping of
      // `concernId`). Cloud schema mirrors verbatim. No created_at
      // column on this table — it's a pure (concern_id, child_id)
      // join.
      parentColumn: 'concern_id',
    ),
  ],
);

const formSubmissionsSpec = TableSpec(
  table: 'form_submissions',
  dateColumns: {'submitted_at', 'review_due_at', 'created_at', 'updated_at'},
);

/// Every spec, in pull order. FK targets first (groups before
/// children that reference them; library items before lesson-
/// sequence-items, etc). Bootstrap iterates this list to pull all
/// tables on sign-in; manual "Sync now" does the same.
const List<TableSpec> kAllSpecs = [
  // Foundation: no FKs out, referenced by many.
  groupsSpec,
  roomsSpec,
  rolesSpec,
  // People — parents → children → adults so FKs land cleanly.
  parentsSpec,
  childrenSpec,
  adultsSpec,
  // Standalone entities.
  vehiclesSpec,
  // Library + sequences (sequences reference library items).
  activityLibrarySpec,
  lessonSequencesSpec,
  themesSpec,
  // Schedule before trips (trips can spawn schedule_entries).
  scheduleTemplatesSpec,
  tripsSpec,
  scheduleEntriesSpec,
  // Forms — observations + concerns + polymorphic forms.
  observationsSpec,
  parentConcernNotesSpec,
  formSubmissionsSpec,
];
