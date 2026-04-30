-- Quality-of-life columns surfaced by the app-fit audit. All
-- additive nullable — every existing row is unaffected and reads
-- continue to work exactly as before. UI rolls out incrementally;
-- the columns travel through sync as soon as the corresponding
-- Drift schema bump (v52) lands.
--
-- WHY each column:
--
-- 1. `archived_at timestamptz` — "hide but don't delete." Programs
--    accumulate alumni children, ex-staff, retired vehicles, and
--    rooms under renovation across years. Today the only verb is
--    delete (which sets-null FKs and erases audit context for
--    historical observations / attendance). Pickers will filter
--    on `archived_at IS NULL`; "Show archived" toggles will
--    relax the filter.
--
-- 2. `position int` — user-orderable lists where teachers expect
--    drag-to-reorder (groups display order on Today, rooms list,
--    roles list, children-within-a-group line-up order). The
--    `lesson_sequence_items.position` precedent shows the
--    pattern works. NULL falls back to alpha by name.
--
-- 3. `created_by uuid` — audit "who entered this." Only on tables
--    where attribution actually shows up in UI: observations
--    ("Logged by Sarah") and form_submissions ("Vehicle check
--    completed by Marcus"). Existing free-text `author_name`
--    on observations stays as a display fallback for legacy
--    rows; new rows populate both, future code reads from the
--    audit FK first.

-- =====================================================================
-- 1. archived_at on entity tables that programs want to keep
--    historically but hide from active pickers
-- =====================================================================

alter table public.groups
  add column if not exists archived_at timestamptz;
alter table public.rooms
  add column if not exists archived_at timestamptz;
alter table public.roles
  add column if not exists archived_at timestamptz;
alter table public.children
  add column if not exists archived_at timestamptz;
alter table public.adults
  add column if not exists archived_at timestamptz;
alter table public.parents
  add column if not exists archived_at timestamptz;
alter table public.vehicles
  add column if not exists archived_at timestamptz;

-- Partial indexes — most rows are not archived, so a partial
-- index over the active set keeps the picker queries fast
-- without indexing every row's null.
create index if not exists idx_groups_active
  on public.groups (program_id)
  where archived_at is null;
create index if not exists idx_rooms_active
  on public.rooms (program_id)
  where archived_at is null;
create index if not exists idx_roles_active
  on public.roles (program_id)
  where archived_at is null;
create index if not exists idx_children_active
  on public.children (program_id)
  where archived_at is null;
create index if not exists idx_adults_active
  on public.adults (program_id)
  where archived_at is null;

-- =====================================================================
-- 2. position columns for user-orderable lists
-- =====================================================================

alter table public.groups
  add column if not exists position integer;
alter table public.rooms
  add column if not exists position integer;
alter table public.roles
  add column if not exists position integer;
-- Children: ordered within a group, so the position semantic is
-- "place in this group's roster line-up." Same column shape;
-- callers sort by group_id, position, first_name.
alter table public.children
  add column if not exists position integer;

-- =====================================================================
-- 3. created_by audit columns (auth user id) on user-authored rows
-- =====================================================================

alter table public.observations
  add column if not exists created_by uuid
  references auth.users(id) on delete set null;

alter table public.form_submissions
  add column if not exists created_by uuid
  references auth.users(id) on delete set null;

create index if not exists idx_observations_created_by
  on public.observations (created_by)
  where created_by is not null;
create index if not exists idx_form_submissions_created_by
  on public.form_submissions (created_by)
  where created_by is not null;
