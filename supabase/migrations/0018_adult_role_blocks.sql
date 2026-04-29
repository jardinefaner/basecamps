-- Per-adult role-block timeline (v48). Two tables:
--
--   * adult_role_blocks            — weekday pattern
--   * adult_role_block_overrides   — date-specific overrides
--
-- Models classroom-rotation patterns: every adult has a sequence
-- of role blocks per weekday saying what role they're in (anchor /
-- specialist / break / etc) and which group they're in for that
-- slot. The resolver layers pattern + overrides for any date.
--
-- Sync:
--   * Both tables are program-scoped (program_id text column).
--   * They sync as cascades of `adults` — pushed alongside the
--     parent adult row, replaced wholesale on push. See
--     sync_specs.dart for the cascade wiring.
--   * Realtime publication + REPLICA IDENTITY FULL added at the
--     end so live edits flow.
--
-- Idempotent (IF NOT EXISTS).

create table if not exists public.adult_role_blocks (
  id text primary key,
  adult_id text not null
    references public.adults(id) on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  start_minute integer not null check (start_minute between 0 and 1440),
  end_minute integer not null check (end_minute between 0 and 1440),
  kind text not null
    check (kind in ('anchor', 'specialist', 'break', 'lunch',
                    'admin', 'sub')),
  subject text,
  group_id text references public.groups(id) on delete set null,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_adult_role_blocks_adult_weekday
  on public.adult_role_blocks (adult_id, weekday);

drop trigger if exists adult_role_blocks_touch on public.adult_role_blocks;
create trigger adult_role_blocks_touch
  before update on public.adult_role_blocks
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- adult_role_block_overrides
-- =====================================================================

create table if not exists public.adult_role_block_overrides (
  id text primary key,
  adult_id text not null
    references public.adults(id) on delete cascade,
  date date not null,
  start_minute integer not null check (start_minute between 0 and 1440),
  end_minute integer not null check (end_minute between 0 and 1440),
  kind text not null
    check (kind in ('anchor', 'specialist', 'break', 'lunch',
                    'admin', 'sub')),
  subject text,
  group_id text references public.groups(id) on delete set null,
  replaces boolean not null default false,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_adult_role_block_overrides_adult_date
  on public.adult_role_block_overrides (adult_id, date);

drop trigger if exists adult_role_block_overrides_touch
  on public.adult_role_block_overrides;
create trigger adult_role_block_overrides_touch
  before update on public.adult_role_block_overrides
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- RLS — both tables scope through their parent adult's program.
-- Same pattern as adult_availability / adult_day_blocks.
-- =====================================================================

alter table public.adult_role_blocks enable row level security;
alter table public.adult_role_block_overrides enable row level security;

drop policy if exists adult_role_blocks_all on public.adult_role_blocks;
create policy adult_role_blocks_all on public.adult_role_blocks
  for all using (
    exists (
      select 1 from public.adults a
       where a.id = adult_role_blocks.adult_id
         and public.is_program_member(a.program_id)
    )
  );

drop policy if exists adult_role_block_overrides_all
  on public.adult_role_block_overrides;
create policy adult_role_block_overrides_all on public.adult_role_block_overrides
  for all using (
    exists (
      select 1 from public.adults a
       where a.id = adult_role_block_overrides.adult_id
         and public.is_program_member(a.program_id)
    )
  );

-- =====================================================================
-- Realtime + REPLICA IDENTITY (matches 0007 + 0017)
-- =====================================================================
--
-- `alter publication ... add table` raises 42710 (duplicate_object)
-- when the table is already a member. Wrap each in a do-block that
-- swallows the duplicate so the migration is safely re-applied (the
-- CLI re-runs the whole pending list and doesn't track partial-fail
-- state per statement).

do $$
begin
  alter publication supabase_realtime add table public.adult_role_blocks;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.adult_role_block_overrides;
exception when duplicate_object then null;
end $$;

alter table public.adult_role_blocks
  replica identity full;
alter table public.adult_role_block_overrides
  replica identity full;
