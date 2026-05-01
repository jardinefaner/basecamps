-- v56: monthly plan persistence (Slice 2) — activities + variants.
--
-- Each (program, group, date) cell can hold N activity variants.
-- Variant 0 is what the teacher typed manually; subsequent variants
-- are AI-generated alternates (∗ button). The schema is one row per
-- variant rather than a JSON blob per cell — that lets the sync
-- engine push individual variant edits as field-level UPDATEs (one
-- variant updated, the rest untouched) and lets RLS / soft-delete /
-- updated_at semantics work the same way they do for every other
-- synced entity.
--
-- Mirrors Drift v56 in lib/database/database.dart.

create table if not exists public.monthly_activities (
  id text primary key,
  program_id text not null
    references public.programs(id) on delete cascade,

  -- (group, date) addresses the cell. group_id is text to match the
  -- Drift-generated text id on public.groups (every cross-table FK
  -- in this schema is text-text — uuid would have forced an extra
  -- conversion).
  group_id text not null
    references public.groups(id) on delete cascade,
  date text not null,  -- "yyyy-MM-dd" — calendar, no timezone

  -- Within (group, date), variants order by position. 0 = manual
  -- entry, 1+ = AI variants in creation order. We don't re-pack on
  -- delete (a variant's position is its identity); sort + render
  -- skips gaps invisibly.
  position integer not null default 0,

  -- Activity content. All nullable so an in-progress empty variant
  -- can persist its draft without a partial-row constraint
  -- violation. The repository's watcher filters out empties for
  -- visual rendering.
  title text,
  description text,
  objectives text,
  steps text,
  materials text,
  link text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Primary query: "every variant for cell (group, date) in this
-- program, in display order." Composite index covers it.
create index if not exists idx_monthly_activities_cell
  on public.monthly_activities (program_id, group_id, date, position)
  where deleted_at is null;

-- Secondary: standard updated_at index for the sync engine's
-- since-cursor pulls. Matches the shape every other entity uses.
create index if not exists idx_monthly_activities_program_updated
  on public.monthly_activities (program_id, updated_at);

drop trigger if exists monthly_activities_touch on public.monthly_activities;
create trigger monthly_activities_touch
  before update on public.monthly_activities
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- RLS — same shape as every other program-scoped entity.
-- =====================================================================

alter table public.monthly_activities enable row level security;

drop policy if exists monthly_activities_select on public.monthly_activities;
create policy monthly_activities_select on public.monthly_activities
  for select using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = monthly_activities.program_id
        and m.user_id = auth.uid()
    )
  );
drop policy if exists monthly_activities_insert on public.monthly_activities;
create policy monthly_activities_insert on public.monthly_activities
  for insert with check (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = monthly_activities.program_id
        and m.user_id = auth.uid()
    )
  );
drop policy if exists monthly_activities_update on public.monthly_activities;
create policy monthly_activities_update on public.monthly_activities
  for update using (
    program_id is not null and exists (
      select 1 from public.program_members m
      where m.program_id = monthly_activities.program_id
        and m.user_id = auth.uid()
    )
  );

-- Realtime publication
alter publication supabase_realtime add table public.monthly_activities;
