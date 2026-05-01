-- v55: monthly plan persistence (Slice 1) — themes + sub-themes.
--
-- Two small program-scoped tables that survive app restart and ride
-- the realtime channel so two teachers planning the same month see
-- each other's changes within the second. Activities (the bulk of
-- the plan) come in a follow-up slice; getting themes/sub-themes
-- right first is intentional — they're the *anchor context* every
-- AI variant prompt uses, so locking them in eliminates drift in
-- generated activities before we cloud-back the activities tier.
--
-- Schema follows the established Tier-1 entity shape: text id (so
-- the client can construct it deterministically — `${program}|${ym}`
-- — and upserts compose without round-tripping through generated
-- ids), program_id FK with cascade delete, created_at/updated_at
-- audit columns, deleted_at tombstone for soft-delete via UPDATE.
--
-- Mirrors Drift v55 in lib/database/database.dart.

-- =====================================================================
-- monthly_themes — one row per (program, month). A "year_month" text
-- column stores the period as "yyyy-mm" so the client can look up by
-- a stable key without timezone math (months don't carry any
-- meaningful time component).
-- =====================================================================

create table if not exists public.monthly_themes (
  id text primary key,
  program_id text not null
    references public.programs(id) on delete cascade,
  year_month text not null,  -- "yyyy-mm" — e.g. "2026-05"
  theme text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- One theme row per (program, month). Without this, two clients
-- racing to set a theme for the same month end up with two rows
-- and the UI doesn't know which to render. The unique constraint
-- + composite-id pattern keeps both client and server in sync on
-- "this is THE row for May 2026."
create unique index if not exists ux_monthly_themes_program_month
  on public.monthly_themes (program_id, year_month)
  where deleted_at is null;

create index if not exists idx_monthly_themes_program_updated
  on public.monthly_themes (program_id, updated_at);

drop trigger if exists monthly_themes_touch on public.monthly_themes;
create trigger monthly_themes_touch
  before update on public.monthly_themes
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- weekly_subthemes — one row per (program, ISO Monday date). The
-- monthly plan groups days into weeks at the Monday boundary, so the
-- per-week sub-theme is keyed off Monday's date in "yyyy-MM-dd" form.
-- Storing as text (not timestamptz) for the same reason as
-- monthly_themes.year_month: the date is a calendar identifier, not
-- an instant.
-- =====================================================================

create table if not exists public.weekly_subthemes (
  id text primary key,
  program_id text not null
    references public.programs(id) on delete cascade,
  monday_date text not null,  -- "yyyy-MM-dd" — e.g. "2026-05-04"
  sub_theme text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists ux_weekly_subthemes_program_monday
  on public.weekly_subthemes (program_id, monday_date)
  where deleted_at is null;

create index if not exists idx_weekly_subthemes_program_updated
  on public.weekly_subthemes (program_id, updated_at);

drop trigger if exists weekly_subthemes_touch on public.weekly_subthemes;
create trigger weekly_subthemes_touch
  before update on public.weekly_subthemes
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- RLS — same shape as every other program-scoped entity. Members of
-- the program can SELECT / INSERT / UPDATE; no DELETE policy (callers
-- soft-delete via deleted_at).
-- =====================================================================

alter table public.monthly_themes enable row level security;
alter table public.weekly_subthemes enable row level security;

-- monthly_themes
drop policy if exists monthly_themes_select on public.monthly_themes;
create policy monthly_themes_select on public.monthly_themes
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = monthly_themes.program_id
        and m.user_id = auth.uid()
    )
  );
drop policy if exists monthly_themes_insert on public.monthly_themes;
create policy monthly_themes_insert on public.monthly_themes
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = monthly_themes.program_id
        and m.user_id = auth.uid()
    )
  );
drop policy if exists monthly_themes_update on public.monthly_themes;
create policy monthly_themes_update on public.monthly_themes
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = monthly_themes.program_id
        and m.user_id = auth.uid()
    )
  );

-- weekly_subthemes
drop policy if exists weekly_subthemes_select on public.weekly_subthemes;
create policy weekly_subthemes_select on public.weekly_subthemes
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = weekly_subthemes.program_id
        and m.user_id = auth.uid()
    )
  );
drop policy if exists weekly_subthemes_insert on public.weekly_subthemes;
create policy weekly_subthemes_insert on public.weekly_subthemes
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = weekly_subthemes.program_id
        and m.user_id = auth.uid()
    )
  );
drop policy if exists weekly_subthemes_update on public.weekly_subthemes;
create policy weekly_subthemes_update on public.weekly_subthemes
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = weekly_subthemes.program_id
        and m.user_id = auth.uid()
    )
  );

-- =====================================================================
-- Realtime publication — both tables join the supabase_realtime
-- publication so the sync engine's existing onPostgresChanges
-- listener (filter: program_id = active) picks them up automatically.
-- =====================================================================

alter publication supabase_realtime add table public.monthly_themes;
alter publication supabase_realtime add table public.weekly_subthemes;
