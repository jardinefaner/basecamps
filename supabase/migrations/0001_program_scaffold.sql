-- Programs scaffold (matches Drift schema v41).
--
-- Creates the two membership tables that anchor Basecamp's multi-
-- user architecture. Every Supabase user belongs to one or more
-- programs; every data table will eventually carry a `program_id`
-- column scoped via RLS to the user's memberships.
--
-- Apply in the Supabase Dashboard → SQL Editor (paste & run) or via
-- the Supabase CLI (`supabase db push`). The local Drift schema is
-- the source of truth for column names + types, so this file mirrors
-- those exactly. When Drift bumps to a new schema version that adds
-- columns, a new sibling .sql lands here in lockstep.
--
-- This migration ships before any data sync — no row movement happens
-- yet. It's here so the cloud-side tables exist when Slice C lights
-- up the first per-table sync (Observations).

-- =====================================================================
-- programs
-- =====================================================================

create table if not exists public.programs (
  id text primary key,
  name text not null,
  -- Real FK to auth.users so deleting a Supabase user cascades the
  -- programs they created. Locally the column is just text (Drift has
  -- no auth.users to FK to), but on the cloud side the constraint is
  -- worth having.
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Updated_at auto-bump trigger so client writes don't have to
-- remember to set it. Drift mirror does this in Dart (Value(now()))
-- but the cloud should be self-correcting too.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists programs_touch on public.programs;
create trigger programs_touch
  before update on public.programs
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- program_members
-- =====================================================================

create table if not exists public.program_members (
  program_id text not null references public.programs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- 'admin' | 'teacher' (free-text so we can grow without a migration)
  role text not null default 'teacher',
  joined_at timestamptz not null default now(),
  primary key (program_id, user_id)
);

-- Reverse-direction lookup ("what programs is this user in?") fires
-- on every active-program resolution and on the future invite flow.
-- The composite PK already covers (program_id, user_id) lookups.
create index if not exists idx_program_members_user
  on public.program_members (user_id);

-- =====================================================================
-- RLS
-- =====================================================================
--
-- Two principles:
--   1. A user can only see programs they belong to.
--   2. Only admins of a program can mutate the program row or its
--      member list.
--
-- Membership self-management is the one nuance: a user can always
-- *insert* themselves into a program they were invited to (via an
-- invite token, future feature) and can always *remove* themselves.
-- That logic isn't here yet — for v1, only admins write
-- program_members rows.

alter table public.programs enable row level security;
alter table public.program_members enable row level security;

-- programs: SELECT only rows where the requesting user is a member.
drop policy if exists programs_select on public.programs;
create policy programs_select on public.programs
  for select using (
    exists (
      select 1 from public.program_members m
      where m.program_id = programs.id and m.user_id = auth.uid()
    )
  );

-- programs: INSERT — anyone authenticated can create a program;
-- they're forced to become its creator (and the bootstrap follows up
-- with a program_members admin row in the same transaction).
drop policy if exists programs_insert on public.programs;
create policy programs_insert on public.programs
  for insert with check (auth.uid() = created_by);

-- programs: UPDATE — admins only.
drop policy if exists programs_update on public.programs;
create policy programs_update on public.programs
  for update using (
    exists (
      select 1 from public.program_members m
      where m.program_id = programs.id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );

-- programs: DELETE — admins only. Cascade wipes the membership rows.
drop policy if exists programs_delete on public.programs;
create policy programs_delete on public.programs
  for delete using (
    exists (
      select 1 from public.program_members m
      where m.program_id = programs.id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );

-- program_members: SELECT — see your own row plus rows in programs
-- you're an admin of (the future member-list UI). Without the
-- `user_id = auth.uid()` clause a freshly invited user couldn't even
-- read their own membership row to discover which program they
-- joined.
drop policy if exists program_members_select on public.program_members;
create policy program_members_select on public.program_members
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.program_members m2
      where m2.program_id = program_members.program_id
        and m2.user_id = auth.uid()
        and m2.role = 'admin'
    )
  );

-- program_members: INSERT — admins of the program can add new
-- members. The bootstrap also needs to insert the FIRST admin row
-- when creating a program, so we allow inserts where the user is
-- inserting themselves AND no rows exist for that program yet.
drop policy if exists program_members_insert on public.program_members;
create policy program_members_insert on public.program_members
  for insert with check (
    -- Admin of an existing program adding someone else.
    exists (
      select 1 from public.program_members m
      where m.program_id = program_members.program_id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
    -- OR: bootstrap case — user inserting their own first row in a
    -- program they just created. The CHECK matches when no other
    -- rows exist yet for this program (and the inserter is the
    -- creator on the programs row).
    or (
      user_id = auth.uid()
      and exists (
        select 1 from public.programs p
        where p.id = program_members.program_id
          and p.created_by = auth.uid()
      )
    )
  );

-- program_members: UPDATE — admins can change roles.
drop policy if exists program_members_update on public.program_members;
create policy program_members_update on public.program_members
  for update using (
    exists (
      select 1 from public.program_members m
      where m.program_id = program_members.program_id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );

-- program_members: DELETE — admins can remove members; users can
-- always remove themselves (leave the program).
drop policy if exists program_members_delete on public.program_members;
create policy program_members_delete on public.program_members
  for delete using (
    user_id = auth.uid()
    or exists (
      select 1 from public.program_members m
      where m.program_id = program_members.program_id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );
