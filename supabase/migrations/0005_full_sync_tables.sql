-- Slice C, full sync surface: every program-scoped Drift table.
--
-- Mirrors lib/database/tables.dart into Postgres so multi-device
-- users see the same program data on every device. Pattern is the
-- one established in 0004_observations_sync.sql:
--
--  - Every column matches Drift's shape verbatim (snake_case names,
--    text for strings, timestamptz for dates, bigint for int,
--    boolean for bool). The client serializer uses these names
--    directly when shipping rows up.
--  - `deleted_at timestamptz null` on every entity table for soft
--    deletes. Clients filter `deleted_at IS NULL` on reads but ship
--    the row up with deleted_at set so other devices learn about
--    the delete on next pull. Cascade tables have no deleted_at —
--    they're hard-deleted because edits to set membership /
--    domain tags / etc are routine and shouldn't leave tombstones.
--  - `program_id` carries a real FK to public.programs(id) with
--    cascade-delete on entity tables. Locally Drift stores plain
--    text; the bootstrap maintains the invariant via Riverpod.
--  - Other context FKs (group_id, child_id, room_id, adult_id,
--    parent_id, etc.) are kept as plain text WITHOUT cloud FK
--    constraints in this migration. Constraints would couple the
--    apply order tightly and complicate cascade semantics; we rely
--    on the client to maintain referential integrity (Drift
--    already enforces it locally) and let cloud catch up when
--    individual tables harden their FKs in follow-ups.
--  - Every entity table gets the touch_updated_at trigger from
--    0001 plus an (program_id, updated_at) index for the pull-on-
--    launch delta query. Cascade tables index their parent FK.
--
-- Observations + its three cascades (observation_children,
-- observation_attachments, observation_domain_tags) are
-- INTENTIONALLY ABSENT — they already shipped in 0004. Re-creating
-- them here would conflict with that migration.
--
-- RLS shape (mirrors 0004):
--  - Entity tables: SELECT/INSERT/UPDATE policies scoped to
--    program_members. NO DELETE policy — soft-delete via UPDATE.
--  - Cascade tables: a single ALL policy threading through the
--    parent's program_members membership. DELETE is allowed
--    because membership-style joins are routinely edited.

-- =====================================================================
-- groups
-- =====================================================================

create table if not exists public.groups (
  id text primary key,
  name text not null,
  color_hex text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_groups_program_updated
  on public.groups (program_id, updated_at);

drop trigger if exists groups_touch on public.groups;
create trigger groups_touch
  before update on public.groups
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- rooms
-- =====================================================================

create table if not exists public.rooms (
  id text primary key,
  name text not null,
  capacity bigint,
  notes text,
  default_for_group_id text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_rooms_program_updated
  on public.rooms (program_id, updated_at);

drop trigger if exists rooms_touch on public.rooms;
create trigger rooms_touch
  before update on public.rooms
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- roles
-- =====================================================================

create table if not exists public.roles (
  id text primary key,
  name text not null,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_roles_program_updated
  on public.roles (program_id, updated_at);

drop trigger if exists roles_touch on public.roles;
create trigger roles_touch
  before update on public.roles
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- parents
-- =====================================================================

create table if not exists public.parents (
  id text primary key,
  first_name text not null,
  last_name text,
  relationship text,
  phone text,
  email text,
  notes text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_parents_program_updated
  on public.parents (program_id, updated_at);

drop trigger if exists parents_touch on public.parents;
create trigger parents_touch
  before update on public.parents
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- parent_children (cascade of parents)
-- =====================================================================

create table if not exists public.parent_children (
  parent_id text not null
    references public.parents(id) on delete cascade,
  child_id text not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (parent_id, child_id)
);

create index if not exists idx_parent_children_parent
  on public.parent_children (parent_id);

-- =====================================================================
-- children
-- =====================================================================

create table if not exists public.children (
  id text primary key,
  first_name text not null,
  last_name text,
  group_id text,
  birth_date timestamptz,
  pin text,
  notes text,
  parent_name text,
  avatar_path text,
  expected_arrival text,
  expected_pickup text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_children_program_updated
  on public.children (program_id, updated_at);

drop trigger if exists children_touch on public.children;
create trigger children_touch
  before update on public.children
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- child_schedule_overrides (cascade of children)
-- =====================================================================

create table if not exists public.child_schedule_overrides (
  id text primary key,
  child_id text not null
    references public.children(id) on delete cascade,
  date timestamptz not null,
  expected_arrival_override text,
  expected_pickup_override text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_child_schedule_overrides_child
  on public.child_schedule_overrides (child_id);

-- =====================================================================
-- attendance (cascade of children)
-- =====================================================================
--
-- Composite PK (child_id, date) matches Drift. Drift stores
-- clock_time / pickup_time as text HH:mm strings, NOT timestamps;
-- they're carried through verbatim. (sync_specs.dart's mention of
-- arrived_at / departed_at date columns appears to be stale — the
-- Drift schema has no such columns. See migration anomalies note.)

create table if not exists public.attendance (
  child_id text not null
    references public.children(id) on delete cascade,
  date timestamptz not null,
  status text not null,
  clock_time text,
  notes text,
  pickup_time text,
  picked_up_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (child_id, date)
);

create index if not exists idx_attendance_child
  on public.attendance (child_id);

-- =====================================================================
-- adults
-- =====================================================================
--
-- Note: there is NO `adult_name` column. The free-text adult name
-- on schedule_templates / schedule_entries is a different, deprecated
-- field on those tables. The Adults Drift class only carries `name`.

create table if not exists public.adults (
  id text primary key,
  name text not null,
  role text,
  role_id text,
  notes text,
  avatar_path text,
  phone text,
  email text,
  parent_id text,
  adult_role text not null default 'adult',
  anchored_group_id text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_adults_program_updated
  on public.adults (program_id, updated_at);

drop trigger if exists adults_touch on public.adults;
create trigger adults_touch
  before update on public.adults
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- adult_availability (cascade of adults)
-- =====================================================================

create table if not exists public.adult_availability (
  id text primary key,
  adult_id text not null
    references public.adults(id) on delete cascade,
  day_of_week bigint not null,
  start_time text not null,
  end_time text not null,
  start_date timestamptz,
  end_date timestamptz,
  break_start text,
  break_end text,
  break2_start text,
  break2_end text,
  lunch_start text,
  lunch_end text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_adult_availability_adult
  on public.adult_availability (adult_id);

-- =====================================================================
-- adult_day_blocks (cascade of adults)
-- =====================================================================

create table if not exists public.adult_day_blocks (
  id text primary key,
  adult_id text not null
    references public.adults(id) on delete cascade,
  day_of_week bigint not null,
  start_time text not null,
  end_time text not null,
  role text not null,
  group_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_adult_day_blocks_adult
  on public.adult_day_blocks (adult_id);

-- =====================================================================
-- vehicles
-- =====================================================================

create table if not exists public.vehicles (
  id text primary key,
  name text not null,
  make_model text not null default '',
  license_plate text not null default '',
  notes text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_vehicles_program_updated
  on public.vehicles (program_id, updated_at);

drop trigger if exists vehicles_touch on public.vehicles;
create trigger vehicles_touch
  before update on public.vehicles
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- trips
-- =====================================================================

create table if not exists public.trips (
  id text primary key,
  name text not null,
  date timestamptz not null,
  end_date timestamptz,
  location text,
  notes text,
  departure_time text,
  return_time text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_trips_program_updated
  on public.trips (program_id, updated_at);

drop trigger if exists trips_touch on public.trips;
create trigger trips_touch
  before update on public.trips
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- trip_groups (cascade of trips)
-- =====================================================================

create table if not exists public.trip_groups (
  trip_id text not null
    references public.trips(id) on delete cascade,
  group_id text not null,
  primary key (trip_id, group_id)
);

create index if not exists idx_trip_groups_trip
  on public.trip_groups (trip_id);

-- =====================================================================
-- activity_library
-- =====================================================================

create table if not exists public.activity_library (
  id text primary key,
  title text not null,
  default_duration_min bigint,
  adult_id text,
  location text,
  notes text,
  audience_min_age bigint,
  audience_max_age bigint,
  hook text,
  summary text,
  key_points text,
  learning_goals text,
  engagement_time_min bigint,
  source_url text,
  source_attribution text,
  materials text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_activity_library_program_updated
  on public.activity_library (program_id, updated_at);

drop trigger if exists activity_library_touch on public.activity_library;
create trigger activity_library_touch
  before update on public.activity_library
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- activity_library_domain_tags (cascade of activity_library)
-- =====================================================================

create table if not exists public.activity_library_domain_tags (
  library_item_id text not null
    references public.activity_library(id) on delete cascade,
  domain text not null,
  primary key (library_item_id, domain)
);

create index if not exists idx_activity_library_domain_tags_item
  on public.activity_library_domain_tags (library_item_id);

-- =====================================================================
-- activity_library_usages (cascade of activity_library)
-- =====================================================================

create table if not exists public.activity_library_usages (
  id text primary key,
  library_item_id text not null
    references public.activity_library(id) on delete cascade,
  template_id text,
  entry_id text,
  used_on timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_activity_library_usages_item
  on public.activity_library_usages (library_item_id);

-- =====================================================================
-- lesson_sequences
-- =====================================================================

create table if not exists public.lesson_sequences (
  id text primary key,
  name text not null,
  description text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_lesson_sequences_program_updated
  on public.lesson_sequences (program_id, updated_at);

drop trigger if exists lesson_sequences_touch on public.lesson_sequences;
create trigger lesson_sequences_touch
  before update on public.lesson_sequences
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- lesson_sequence_items (cascade of lesson_sequences)
-- =====================================================================

create table if not exists public.lesson_sequence_items (
  id text primary key,
  sequence_id text not null
    references public.lesson_sequences(id) on delete cascade,
  library_item_id text not null,
  position bigint not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_lesson_sequence_items_sequence
  on public.lesson_sequence_items (sequence_id);

-- =====================================================================
-- themes
-- =====================================================================

create table if not exists public.themes (
  id text primary key,
  name text not null,
  color_hex text,
  start_date timestamptz not null,
  end_date timestamptz not null,
  notes text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_themes_program_updated
  on public.themes (program_id, updated_at);

drop trigger if exists themes_touch on public.themes;
create trigger themes_touch
  before update on public.themes
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- schedule_templates
-- =====================================================================

create table if not exists public.schedule_templates (
  id text primary key,
  day_of_week bigint not null,
  start_time text not null,
  end_time text not null,
  is_full_day boolean not null default false,
  title text not null,
  series_id text,
  group_id text,
  all_groups boolean not null default true,
  adult_name text,
  adult_id text,
  location text,
  notes text,
  start_date timestamptz,
  end_date timestamptz,
  source_library_item_id text,
  room_id text,
  source_url text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_schedule_templates_program_updated
  on public.schedule_templates (program_id, updated_at);

drop trigger if exists schedule_templates_touch on public.schedule_templates;
create trigger schedule_templates_touch
  before update on public.schedule_templates
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- template_groups (cascade of schedule_templates)
-- =====================================================================

create table if not exists public.template_groups (
  template_id text not null
    references public.schedule_templates(id) on delete cascade,
  group_id text not null,
  primary key (template_id, group_id)
);

create index if not exists idx_template_groups_template
  on public.template_groups (template_id);

-- =====================================================================
-- schedule_entries
-- =====================================================================

create table if not exists public.schedule_entries (
  id text primary key,
  date timestamptz not null,
  end_date timestamptz,
  start_time text not null,
  end_time text not null,
  is_full_day boolean not null default false,
  title text not null,
  group_id text,
  all_groups boolean not null default true,
  adult_name text,
  adult_id text,
  location text,
  notes text,
  kind text not null,
  source_trip_id text,
  overrides_template_id text,
  source_library_item_id text,
  room_id text,
  source_url text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_schedule_entries_program_updated
  on public.schedule_entries (program_id, updated_at);

drop trigger if exists schedule_entries_touch on public.schedule_entries;
create trigger schedule_entries_touch
  before update on public.schedule_entries
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- entry_groups (cascade of schedule_entries)
-- =====================================================================

create table if not exists public.entry_groups (
  entry_id text not null
    references public.schedule_entries(id) on delete cascade,
  group_id text not null,
  primary key (entry_id, group_id)
);

create index if not exists idx_entry_groups_entry
  on public.entry_groups (entry_id);

-- =====================================================================
-- parent_concern_notes
-- =====================================================================

create table if not exists public.parent_concern_notes (
  id text primary key,
  child_names text not null default '',
  parent_name text not null default '',
  concern_date timestamptz,
  staff_receiving text not null default '',
  supervisor_notified text,
  method_in_person boolean not null default false,
  method_phone boolean not null default false,
  method_email boolean not null default false,
  method_other text,
  concern_description text not null default '',
  immediate_response text not null default '',
  follow_up_monitor boolean not null default false,
  follow_up_staff_check_ins boolean not null default false,
  follow_up_supervisor_review boolean not null default false,
  follow_up_parent_conversation boolean not null default false,
  follow_up_other text,
  follow_up_date timestamptz,
  additional_notes text,
  staff_signature text,
  staff_signature_path text,
  staff_signature_date timestamptz,
  supervisor_signature text,
  supervisor_signature_path text,
  supervisor_signature_date timestamptz,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_parent_concern_notes_program_updated
  on public.parent_concern_notes (program_id, updated_at);

drop trigger if exists parent_concern_notes_touch on public.parent_concern_notes;
create trigger parent_concern_notes_touch
  before update on public.parent_concern_notes
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- parent_concern_children (cascade of parent_concern_notes)
-- =====================================================================
--
-- Mirrors Drift's `concern_id` column verbatim (snake_case of
-- ParentConcernChildren.concernId). No created_at — the join is
-- a pure (concern_id, child_id) PK with no audit columns.

create table if not exists public.parent_concern_children (
  concern_id text not null
    references public.parent_concern_notes(id) on delete cascade,
  child_id text not null,
  primary key (concern_id, child_id)
);

create index if not exists idx_parent_concern_children_concern
  on public.parent_concern_children (concern_id);

-- =====================================================================
-- form_submissions
-- =====================================================================

create table if not exists public.form_submissions (
  id text primary key,
  form_type text not null,
  status text not null default 'draft',
  submitted_at timestamptz,
  author_name text,
  child_id text,
  group_id text,
  trip_id text,
  parent_submission_id text,
  review_due_at timestamptz,
  data text not null default '{}',
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_form_submissions_program_updated
  on public.form_submissions (program_id, updated_at);

drop trigger if exists form_submissions_touch on public.form_submissions;
create trigger form_submissions_touch
  before update on public.form_submissions
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- RLS — enable on every table
-- =====================================================================

alter table public.groups enable row level security;
alter table public.rooms enable row level security;
alter table public.roles enable row level security;
alter table public.parents enable row level security;
alter table public.parent_children enable row level security;
alter table public.children enable row level security;
alter table public.child_schedule_overrides enable row level security;
alter table public.attendance enable row level security;
alter table public.adults enable row level security;
alter table public.adult_availability enable row level security;
alter table public.adult_day_blocks enable row level security;
alter table public.vehicles enable row level security;
alter table public.trips enable row level security;
alter table public.trip_groups enable row level security;
alter table public.activity_library enable row level security;
alter table public.activity_library_domain_tags enable row level security;
alter table public.activity_library_usages enable row level security;
alter table public.lesson_sequences enable row level security;
alter table public.lesson_sequence_items enable row level security;
alter table public.themes enable row level security;
alter table public.schedule_templates enable row level security;
alter table public.template_groups enable row level security;
alter table public.schedule_entries enable row level security;
alter table public.entry_groups enable row level security;
alter table public.parent_concern_notes enable row level security;
alter table public.parent_concern_children enable row level security;
alter table public.form_submissions enable row level security;

-- =====================================================================
-- RLS — entity table policies (SELECT / INSERT / UPDATE)
-- =====================================================================
--
-- No DELETE policy on entity tables: callers soft-delete by
-- UPDATE'ing deleted_at. Same shape 0004 set up for observations.

-- groups
drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = groups.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists groups_insert on public.groups;
create policy groups_insert on public.groups
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = groups.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists groups_update on public.groups;
create policy groups_update on public.groups
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = groups.program_id and m.user_id = auth.uid()
    )
  );

-- rooms
drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = rooms.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists rooms_insert on public.rooms;
create policy rooms_insert on public.rooms
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = rooms.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists rooms_update on public.rooms;
create policy rooms_update on public.rooms
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = rooms.program_id and m.user_id = auth.uid()
    )
  );

-- roles
drop policy if exists roles_select on public.roles;
create policy roles_select on public.roles
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = roles.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists roles_insert on public.roles;
create policy roles_insert on public.roles
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = roles.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists roles_update on public.roles;
create policy roles_update on public.roles
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = roles.program_id and m.user_id = auth.uid()
    )
  );

-- parents
drop policy if exists parents_select on public.parents;
create policy parents_select on public.parents
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = parents.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists parents_insert on public.parents;
create policy parents_insert on public.parents
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = parents.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists parents_update on public.parents;
create policy parents_update on public.parents
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = parents.program_id and m.user_id = auth.uid()
    )
  );

-- children
drop policy if exists children_select on public.children;
create policy children_select on public.children
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = children.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists children_insert on public.children;
create policy children_insert on public.children
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = children.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists children_update on public.children;
create policy children_update on public.children
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = children.program_id and m.user_id = auth.uid()
    )
  );

-- adults
drop policy if exists adults_select on public.adults;
create policy adults_select on public.adults
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = adults.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists adults_insert on public.adults;
create policy adults_insert on public.adults
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = adults.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists adults_update on public.adults;
create policy adults_update on public.adults
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = adults.program_id and m.user_id = auth.uid()
    )
  );

-- vehicles
drop policy if exists vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = vehicles.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists vehicles_insert on public.vehicles;
create policy vehicles_insert on public.vehicles
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = vehicles.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists vehicles_update on public.vehicles;
create policy vehicles_update on public.vehicles
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = vehicles.program_id and m.user_id = auth.uid()
    )
  );

-- trips
drop policy if exists trips_select on public.trips;
create policy trips_select on public.trips
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = trips.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists trips_insert on public.trips;
create policy trips_insert on public.trips
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = trips.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists trips_update on public.trips;
create policy trips_update on public.trips
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = trips.program_id and m.user_id = auth.uid()
    )
  );

-- activity_library
drop policy if exists activity_library_select on public.activity_library;
create policy activity_library_select on public.activity_library
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = activity_library.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists activity_library_insert on public.activity_library;
create policy activity_library_insert on public.activity_library
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = activity_library.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists activity_library_update on public.activity_library;
create policy activity_library_update on public.activity_library
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = activity_library.program_id and m.user_id = auth.uid()
    )
  );

-- lesson_sequences
drop policy if exists lesson_sequences_select on public.lesson_sequences;
create policy lesson_sequences_select on public.lesson_sequences
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = lesson_sequences.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists lesson_sequences_insert on public.lesson_sequences;
create policy lesson_sequences_insert on public.lesson_sequences
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = lesson_sequences.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists lesson_sequences_update on public.lesson_sequences;
create policy lesson_sequences_update on public.lesson_sequences
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = lesson_sequences.program_id and m.user_id = auth.uid()
    )
  );

-- themes
drop policy if exists themes_select on public.themes;
create policy themes_select on public.themes
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = themes.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists themes_insert on public.themes;
create policy themes_insert on public.themes
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = themes.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists themes_update on public.themes;
create policy themes_update on public.themes
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = themes.program_id and m.user_id = auth.uid()
    )
  );

-- schedule_templates
drop policy if exists schedule_templates_select on public.schedule_templates;
create policy schedule_templates_select on public.schedule_templates
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = schedule_templates.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists schedule_templates_insert on public.schedule_templates;
create policy schedule_templates_insert on public.schedule_templates
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = schedule_templates.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists schedule_templates_update on public.schedule_templates;
create policy schedule_templates_update on public.schedule_templates
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = schedule_templates.program_id and m.user_id = auth.uid()
    )
  );

-- schedule_entries
drop policy if exists schedule_entries_select on public.schedule_entries;
create policy schedule_entries_select on public.schedule_entries
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = schedule_entries.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists schedule_entries_insert on public.schedule_entries;
create policy schedule_entries_insert on public.schedule_entries
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = schedule_entries.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists schedule_entries_update on public.schedule_entries;
create policy schedule_entries_update on public.schedule_entries
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = schedule_entries.program_id and m.user_id = auth.uid()
    )
  );

-- parent_concern_notes
drop policy if exists parent_concern_notes_select on public.parent_concern_notes;
create policy parent_concern_notes_select on public.parent_concern_notes
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = parent_concern_notes.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists parent_concern_notes_insert on public.parent_concern_notes;
create policy parent_concern_notes_insert on public.parent_concern_notes
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = parent_concern_notes.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists parent_concern_notes_update on public.parent_concern_notes;
create policy parent_concern_notes_update on public.parent_concern_notes
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = parent_concern_notes.program_id and m.user_id = auth.uid()
    )
  );

-- form_submissions
drop policy if exists form_submissions_select on public.form_submissions;
create policy form_submissions_select on public.form_submissions
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = form_submissions.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists form_submissions_insert on public.form_submissions;
create policy form_submissions_insert on public.form_submissions
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = form_submissions.program_id and m.user_id = auth.uid()
    )
  );
drop policy if exists form_submissions_update on public.form_submissions;
create policy form_submissions_update on public.form_submissions
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = form_submissions.program_id and m.user_id = auth.uid()
    )
  );

-- =====================================================================
-- RLS — cascade table policies (single ALL policy via parent program)
-- =====================================================================

drop policy if exists parent_children_all on public.parent_children;
create policy parent_children_all on public.parent_children
  for all using (
    exists (
      select 1 from public.parents p
      join public.program_members m on m.program_id = p.program_id
      where p.id = parent_children.parent_id and m.user_id = auth.uid()
    )
  );

drop policy if exists child_schedule_overrides_all on public.child_schedule_overrides;
create policy child_schedule_overrides_all on public.child_schedule_overrides
  for all using (
    exists (
      select 1 from public.children c
      join public.program_members m on m.program_id = c.program_id
      where c.id = child_schedule_overrides.child_id and m.user_id = auth.uid()
    )
  );

drop policy if exists attendance_all on public.attendance;
create policy attendance_all on public.attendance
  for all using (
    exists (
      select 1 from public.children c
      join public.program_members m on m.program_id = c.program_id
      where c.id = attendance.child_id and m.user_id = auth.uid()
    )
  );

drop policy if exists adult_availability_all on public.adult_availability;
create policy adult_availability_all on public.adult_availability
  for all using (
    exists (
      select 1 from public.adults a
      join public.program_members m on m.program_id = a.program_id
      where a.id = adult_availability.adult_id and m.user_id = auth.uid()
    )
  );

drop policy if exists adult_day_blocks_all on public.adult_day_blocks;
create policy adult_day_blocks_all on public.adult_day_blocks
  for all using (
    exists (
      select 1 from public.adults a
      join public.program_members m on m.program_id = a.program_id
      where a.id = adult_day_blocks.adult_id and m.user_id = auth.uid()
    )
  );

drop policy if exists trip_groups_all on public.trip_groups;
create policy trip_groups_all on public.trip_groups
  for all using (
    exists (
      select 1 from public.trips t
      join public.program_members m on m.program_id = t.program_id
      where t.id = trip_groups.trip_id and m.user_id = auth.uid()
    )
  );

drop policy if exists activity_library_domain_tags_all on public.activity_library_domain_tags;
create policy activity_library_domain_tags_all on public.activity_library_domain_tags
  for all using (
    exists (
      select 1 from public.activity_library a
      join public.program_members m on m.program_id = a.program_id
      where a.id = activity_library_domain_tags.library_item_id and m.user_id = auth.uid()
    )
  );

drop policy if exists activity_library_usages_all on public.activity_library_usages;
create policy activity_library_usages_all on public.activity_library_usages
  for all using (
    exists (
      select 1 from public.activity_library a
      join public.program_members m on m.program_id = a.program_id
      where a.id = activity_library_usages.library_item_id and m.user_id = auth.uid()
    )
  );

drop policy if exists lesson_sequence_items_all on public.lesson_sequence_items;
create policy lesson_sequence_items_all on public.lesson_sequence_items
  for all using (
    exists (
      select 1 from public.lesson_sequences s
      join public.program_members m on m.program_id = s.program_id
      where s.id = lesson_sequence_items.sequence_id and m.user_id = auth.uid()
    )
  );

drop policy if exists template_groups_all on public.template_groups;
create policy template_groups_all on public.template_groups
  for all using (
    exists (
      select 1 from public.schedule_templates t
      join public.program_members m on m.program_id = t.program_id
      where t.id = template_groups.template_id and m.user_id = auth.uid()
    )
  );

drop policy if exists entry_groups_all on public.entry_groups;
create policy entry_groups_all on public.entry_groups
  for all using (
    exists (
      select 1 from public.schedule_entries e
      join public.program_members m on m.program_id = e.program_id
      where e.id = entry_groups.entry_id and m.user_id = auth.uid()
    )
  );

drop policy if exists parent_concern_children_all on public.parent_concern_children;
create policy parent_concern_children_all on public.parent_concern_children
  for all using (
    exists (
      select 1 from public.parent_concern_notes n
      join public.program_members m on m.program_id = n.program_id
      where n.id = parent_concern_children.concern_id and m.user_id = auth.uid()
    )
  );
