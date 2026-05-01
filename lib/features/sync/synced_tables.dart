/// Single source of truth for which tables participate in
/// program-scoped sync. Pure const list — no Drift / Riverpod /
/// Supabase imports — so it's safe to consume from
/// `database.dart`'s schema-heal and from
/// `programs_repository.dart`'s backfill without creating an
/// import cycle.
///
/// Every consumer of "the synced table list" reads from here:
///   - `_healProgramIdColumns` re-applies v42's ALTER for each
///   - `ProgramsRepository.backfillUntaggedRows` UPDATEs each
///   - `kSpecTiers` in sync_specs.dart asserts that every spec
///     it declares matches a name in this list (compile-time
///     check via the const equality comparison)
///
/// To add a new synced table: append a name here, add a
/// matching `TableSpec` in sync_specs.dart, and write the cloud
/// SQL migration. Schema-heal + backfill pick it up
/// automatically next launch.
///
/// Order matches `kSpecTiers` — foundation tables first, then
/// people + library, then events + forms — so any sequential
/// iteration respects FK dependency direction.
const List<String> kSyncedTableNames = <String>[
  // Tier 1 — foundation
  'groups',
  'rooms',
  'roles',
  'vehicles',
  'themes',
  // v55 (Slice 1) — monthly plan persistence. Theme per
  // (program, calendar month) and sub-theme per (program, ISO
  // Monday). Activities follow in Slice 2.
  'monthly_themes',
  'weekly_subthemes',
  // Tier 2 — people + library
  'parents',
  'children',
  'adults',
  'activity_library',
  'lesson_sequences',
  // v56 (Slice 2) — monthly plan activities. References groups so
  // it sits in tier 2 with the other group-FK entities.
  'monthly_activities',
  // Tier 3 — events + forms
  'schedule_templates',
  'trips',
  'schedule_entries',
  'observations',
  // parent_concern_notes — removed in v45 (commit 8cc3d68 + this).
  // The polymorphic form_submissions row with form_type='parent_concern'
  // replaces it; see definitions/parent_concern.dart.
  'form_submissions',
];
