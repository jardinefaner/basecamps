-- Slice C, table 1: observations + cascades.
--
-- First per-table cloud sync: mirrors Drift's observations,
-- observation_children, observation_attachments, and
-- observation_domain_tags into Postgres so multi-device users see
-- the same observations on every device.
--
-- Schema decisions:
--  - Every column matches Drift's shape verbatim (column names,
--    nullability, types — text for strings, timestamptz for dates,
--    bigint for `int`-typed columns). The client serializer uses
--    these names directly.
--  - `deleted_at timestamptz null` on observations and on each
--    cascade table for soft deletes. The client filters
--    `deleted_at IS NULL` on reads but pushes the row through to
--    cloud with deleted_at set so other devices learn about the
--    delete on next pull. Hard delete resurrects from stale
--    devices; soft delete doesn't.
--  - `program_id` carries a real FK to public.programs(id) with
--    cascade-delete so removing a program wipes its observations
--    from cloud. Locally the same column is just text (Drift has
--    no programs table to FK to, but the bootstrap maintains the
--    invariant via Riverpod).
--  - Other context FKs (child_id, group_id, trip_id, room_id,
--    schedule_source_id) are kept as plain text WITHOUT cloud FK
--    constraints. Those tables don't exist in cloud yet (later
--    Slice C tables); adding FK constraints now would block
--    sync until every dependency lands. Constraints land alongside
--    each table's migration.
--
-- RLS shape:
--  - Members of the program can SELECT/INSERT/UPDATE rows in
--    that program. The check threads through public.program_members.
--  - DELETE goes through soft-delete (UPDATE deleted_at), so we
--    don't grant DELETE on the rows themselves — that prevents
--    accidental permanent loss while still letting users mark a
--    row deleted.
--  - Cascade tables (observation_children, attachments, domain_tags)
--    scope through their parent observation's program.

-- =====================================================================
-- observations
-- =====================================================================

create table if not exists public.observations (
  id text primary key,
  target_kind text not null,
  child_id text,
  group_id text,
  activity_label text,
  domain text not null,
  sentiment text not null,
  note text not null,
  note_original text,
  trip_id text,
  author_name text,
  schedule_source_kind text,
  schedule_source_id text,
  activity_date timestamptz,
  room_id text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Hot read pattern: "give me everything in this program newer than
-- my last sync timestamp." Index on (program_id, updated_at) keeps
-- the pull-on-launch query bounded.
create index if not exists idx_observations_program_updated
  on public.observations (program_id, updated_at);

-- Updated_at auto-bump trigger so server-side updates always reflect
-- the truth, regardless of what the client sent. Reuses the helper
-- from 0001.
drop trigger if exists observations_touch on public.observations;
create trigger observations_touch
  before update on public.observations
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- observation_children (cascade)
-- =====================================================================

create table if not exists public.observation_children (
  observation_id text not null
    references public.observations(id) on delete cascade,
  child_id text not null,
  created_at timestamptz not null default now(),
  primary key (observation_id, child_id)
);

-- =====================================================================
-- observation_attachments (cascade)
-- =====================================================================
--
-- For v1, the row syncs but the local file path doesn't — other
-- devices see the row metadata (kind, durationMs, createdAt) but
-- the file itself stays on the originating device. Storage-backed
-- media sync is a separate slice.

create table if not exists public.observation_attachments (
  id text primary key,
  observation_id text not null
    references public.observations(id) on delete cascade,
  kind text not null,
  -- Local file path on the originating device. Useless on other
  -- devices until Storage sync ships, but kept in cloud so the
  -- cascade row count matches and we can light up file sync later
  -- without a backfill.
  local_path text not null,
  duration_ms bigint,
  created_at timestamptz not null default now()
);

create index if not exists idx_observation_attachments_observation
  on public.observation_attachments (observation_id);

-- =====================================================================
-- observation_domain_tags (cascade)
-- =====================================================================

create table if not exists public.observation_domain_tags (
  observation_id text not null
    references public.observations(id) on delete cascade,
  domain text not null,
  primary key (observation_id, domain)
);

-- =====================================================================
-- RLS
-- =====================================================================
--
-- Membership-scoped. Every read and write checks that the
-- requesting user is a member of the row's program.

alter table public.observations enable row level security;
alter table public.observation_children enable row level security;
alter table public.observation_attachments enable row level security;
alter table public.observation_domain_tags enable row level security;

drop policy if exists observations_select on public.observations;
create policy observations_select on public.observations
  for select using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = observations.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists observations_insert on public.observations;
create policy observations_insert on public.observations
  for insert with check (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = observations.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists observations_update on public.observations;
create policy observations_update on public.observations
  for update using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = observations.program_id
        and m.user_id = auth.uid()
    )
  );

-- No DELETE policy. Hard delete is intentionally disallowed —
-- callers soft-delete by UPDATE'ing deleted_at, which is what
-- the sync layer does. If a future ops need ever requires real
-- delete (e.g., GDPR right-to-erasure), it goes through a
-- service-role admin path, not the regular RLS policies.

-- Cascade tables: scope SELECT/INSERT/UPDATE/DELETE through the
-- parent observation. We do allow DELETE on these so children/
-- domains can be edited freely (a teacher unticking a kid from a
-- multi-kid observation deletes that join row; it has no business
-- being soft-deleted).

drop policy if exists obs_children_all on public.observation_children;
create policy obs_children_all on public.observation_children
  for all using (
    exists (
      select 1 from public.observations o
      join public.program_members m on m.program_id = o.program_id
      where o.id = observation_children.observation_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists obs_attachments_all on public.observation_attachments;
create policy obs_attachments_all on public.observation_attachments
  for all using (
    exists (
      select 1 from public.observations o
      join public.program_members m on m.program_id = o.program_id
      where o.id = observation_attachments.observation_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists obs_domain_tags_all on public.observation_domain_tags;
create policy obs_domain_tags_all on public.observation_domain_tags
  for all using (
    exists (
      select 1 from public.observations o
      join public.program_members m on m.program_id = o.program_id
      where o.id = observation_domain_tags.observation_id
        and m.user_id = auth.uid()
    )
  );
