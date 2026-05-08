-- v64 / cloud migration 0038: calendar tiles + late pickups
-- promoted from in-memory lab state to persistent + cross-device.
--
-- Two tables, both program_id-scoped via RLS. Mirrors the Drift
-- schema column-for-column. JSONB for the calendar_tiles
-- itinerary blob (stays a single column rather than a cascade
-- table — querying within itineraries is rare, blobs are small).

-- =====================================================================
-- calendar_tiles
-- =====================================================================

create table if not exists public.calendar_tiles (
  id text primary key,
  type text not null,                  -- 'trip' | 'event' | 'dayPlan'
  date timestamptz not null,
  group_id text,
  title text not null,
  description text not null default '',
  destination text not null default '',
  start_minutes bigint,
  end_minutes bigint,
  theme text not null default '',
  notes text not null default '',
  itinerary_json text not null default '[]',
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_calendar_tiles_program_updated
  on public.calendar_tiles (program_id, updated_at);
create index if not exists idx_calendar_tiles_program_date
  on public.calendar_tiles (program_id, date);

drop trigger if exists calendar_tiles_touch on public.calendar_tiles;
create trigger calendar_tiles_touch
  before update on public.calendar_tiles
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- late_pickups
-- =====================================================================

create table if not exists public.late_pickups (
  id text primary key,
  date timestamptz not null,
  pickup_minutes bigint not null,
  child_id text,
  child_name text not null,
  parent_name text not null default '',
  reminder_card_given boolean not null default false,
  staff_name text not null default '',
  notes text not null default '',
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_late_pickups_program_updated
  on public.late_pickups (program_id, updated_at);
create index if not exists idx_late_pickups_program_date
  on public.late_pickups (program_id, date);

drop trigger if exists late_pickups_touch on public.late_pickups;
create trigger late_pickups_touch
  before update on public.late_pickups
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- RLS — same shape as observations / surveys: program members can
-- SELECT/INSERT/UPDATE rows in their program.
-- =====================================================================

alter table public.calendar_tiles enable row level security;
alter table public.late_pickups enable row level security;

drop policy if exists calendar_tiles_select on public.calendar_tiles;
create policy calendar_tiles_select on public.calendar_tiles
  for select using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = calendar_tiles.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists calendar_tiles_insert on public.calendar_tiles;
create policy calendar_tiles_insert on public.calendar_tiles
  for insert with check (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = calendar_tiles.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists calendar_tiles_update on public.calendar_tiles;
create policy calendar_tiles_update on public.calendar_tiles
  for update using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = calendar_tiles.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists late_pickups_select on public.late_pickups;
create policy late_pickups_select on public.late_pickups
  for select using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = late_pickups.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists late_pickups_insert on public.late_pickups;
create policy late_pickups_insert on public.late_pickups
  for insert with check (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = late_pickups.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists late_pickups_update on public.late_pickups;
create policy late_pickups_update on public.late_pickups
  for update using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = late_pickups.program_id
        and m.user_id = auth.uid()
    )
  );

-- =====================================================================
-- Realtime — opt both into supabase_realtime so other devices see
-- new rows live. Replica identity FULL so updates carry the full
-- row.
-- =====================================================================

alter table public.calendar_tiles replica identity full;
alter table public.late_pickups replica identity full;

alter publication supabase_realtime add table public.calendar_tiles;
alter publication supabase_realtime add table public.late_pickups;
