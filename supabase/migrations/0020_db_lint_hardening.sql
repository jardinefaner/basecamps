-- Database-linter hardening pass.
--
-- Addresses every warning surfaced by Supabase's lint suite for the
-- current schema:
--
--   * 0001 unindexed_foreign_keys
--       FK columns not covered by an index. Adds the missing
--       indexes for FKs that fall outside their table's PK / existing
--       indexes.
--
--   * 0003 auth_rls_initplan
--       Policies that call `auth.uid()` directly trigger init-plan
--       re-evaluation per row. Rewrites every such policy to either
--       call the `is_program_member` / `is_program_admin` helpers
--       (which are STABLE and wrap `auth.uid()` once) or wrap the
--       call as `(select auth.uid())`.
--
--   * 0011 function_search_path_mutable
--       Functions without an explicit `SET search_path` are open to
--       schema-shadowing attacks. Recreates every public function
--       with `SET search_path = ''` and fully-qualified references.
--
--   * 0028 / 0029 anon_/authenticated_security_definer_function_executable
--       SECURITY DEFINER functions default to `EXECUTE` granted to
--       PUBLIC. REVOKEs from PUBLIC; grants to `authenticated` only
--       for the helpers user queries actually call. The
--       `cleanup_program_backup` trigger function gets revoked from
--       everyone — it's invoked by the trigger, never by users.
--
-- Idempotent: every CREATE is preceded by a DROP IF EXISTS, every
-- function uses CREATE OR REPLACE, every index uses IF NOT EXISTS.
-- Safe to re-apply.
--
-- This migration is purely server-side. The Dart client doesn't see
-- a schema diff, so no Drift bump is needed.

-- =====================================================================
-- Part 1 — Function hardening
-- =====================================================================
--
-- All five public functions get rewritten with `set search_path = ''`
-- (empty) and fully-qualified table/function references inside their
-- bodies. With an empty search_path, an attacker who creates a table
-- in `public` named `program_members` can't shadow ours — Postgres
-- requires the explicit `public.program_members` qualifier we use.
--
-- SECURITY DEFINER funcs get their EXECUTE revoked from PUBLIC.
-- Helpers that user queries call (is_program_member / is_program_admin
-- / whoami) get re-granted to `authenticated`.
-- `cleanup_program_backup` is a trigger function — nothing user-facing
-- needs to call it, so PUBLIC revoke is the whole story.

-- ── touch_updated_at (trigger function used by every entity table)
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end $$;
revoke all on function public.touch_updated_at() from public;

-- ── is_program_member (RLS helper — STABLE SECURITY DEFINER)
create or replace function public.is_program_member(p_program_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.program_members m
     where m.program_id = p_program_id
       and m.user_id = auth.uid()
  );
$$;
revoke all on function public.is_program_member(text) from public;
grant execute on function public.is_program_member(text) to authenticated;

-- ── is_program_admin (RLS helper — STABLE SECURITY DEFINER)
create or replace function public.is_program_admin(p_program_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.program_members m
     where m.program_id = p_program_id
       and m.user_id = auth.uid()
       and m.role = 'admin'
  );
$$;
revoke all on function public.is_program_admin(text) from public;
grant execute on function public.is_program_admin(text) to authenticated;

-- ── cleanup_program_backup (trigger function — DELETE from storage on
--    program delete). SECURITY DEFINER because it touches storage.objects
--    which has its own RLS that the program-creator wouldn't satisfy.
create or replace function public.cleanup_program_backup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from storage.objects
   where bucket_id = 'db_backups'
     and (storage.foldername(name))[1] = old.id;
  return old;
end $$;
revoke all on function public.cleanup_program_backup() from public;

-- ── whoami (diagnostic RPC — INVOKER, just needs search_path locked)
create or replace function public.whoami()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(auth.uid()::text, '')
$$;
revoke all on function public.whoami() from public;
grant execute on function public.whoami() to authenticated;

-- =====================================================================
-- Part 2 — RLS policies: wrap auth.uid() in scalar subqueries; route
-- inline EXISTS-on-program_members through the helpers
-- =====================================================================
--
-- Two transformations applied to every policy that touched auth.uid():
--   (a) Direct comparisons:  `auth.uid() = X` → `(select auth.uid()) = X`.
--   (b) Inline membership EXISTS:
--           exists (select 1 from public.program_members m
--                    where m.program_id = T.program_id
--                      and m.user_id = auth.uid())
--       → public.is_program_member(T.program_id)
--
-- The helpers are STABLE — Postgres caches their result inside a
-- single statement, eliminating per-row re-evaluation. Direct
-- `(select auth.uid())` does the same for top-level comparisons.

-- ── programs ─────────────────────────────────────────────────────
drop policy if exists programs_select on public.programs;
create policy programs_select on public.programs
  for select using ( public.is_program_member(programs.id) );

drop policy if exists programs_insert on public.programs;
create policy programs_insert on public.programs
  for insert with check ((select auth.uid()) = created_by);

drop policy if exists programs_update on public.programs;
create policy programs_update on public.programs
  for update using ( public.is_program_admin(programs.id) );

drop policy if exists programs_delete on public.programs;
create policy programs_delete on public.programs
  for delete using ( public.is_program_admin(programs.id) );

-- ── program_members ─────────────────────────────────────────────
drop policy if exists program_members_select on public.program_members;
create policy program_members_select on public.program_members
  for select using (
    user_id = (select auth.uid())
    or public.is_program_member(program_members.program_id)
  );

drop policy if exists program_members_insert on public.program_members;
create policy program_members_insert on public.program_members
  for insert with check (
    -- Admin of an existing program adding someone.
    public.is_program_admin(program_members.program_id)
    -- OR: bootstrap case — creator inserting their own first row.
    or (
      user_id = (select auth.uid())
      and exists (
        select 1 from public.programs p
        where p.id = program_members.program_id
          and p.created_by = (select auth.uid())
      )
    )
  );

drop policy if exists program_members_update on public.program_members;
create policy program_members_update on public.program_members
  for update using (
    public.is_program_admin(program_members.program_id)
  );

drop policy if exists program_members_delete on public.program_members;
create policy program_members_delete on public.program_members
  for delete using (
    user_id = (select auth.uid())
    or public.is_program_admin(program_members.program_id)
  );

-- ── program_invites ──────────────────────────────────────────────
drop policy if exists program_invites_select on public.program_invites;
create policy program_invites_select on public.program_invites
  for select using (
    public.is_program_admin(program_invites.program_id)
  );

drop policy if exists program_invites_insert on public.program_invites;
create policy program_invites_insert on public.program_invites
  for insert with check (
    created_by = (select auth.uid())
    and public.is_program_admin(program_invites.program_id)
  );

drop policy if exists program_invites_update on public.program_invites;
create policy program_invites_update on public.program_invites
  for update using (
    public.is_program_admin(program_invites.program_id)
  );

drop policy if exists program_invites_delete on public.program_invites;
create policy program_invites_delete on public.program_invites
  for delete using (
    public.is_program_admin(program_invites.program_id)
  );

-- ── observations ─────────────────────────────────────────────────
drop policy if exists observations_select on public.observations;
create policy observations_select on public.observations
  for select using (
    program_id is not null
    and public.is_program_member(observations.program_id)
  );

drop policy if exists observations_insert on public.observations;
create policy observations_insert on public.observations
  for insert with check (
    program_id is not null
    and public.is_program_member(observations.program_id)
  );

drop policy if exists observations_update on public.observations;
create policy observations_update on public.observations
  for update using (
    program_id is not null
    and public.is_program_member(observations.program_id)
  );

-- ── observation cascades — scope through the parent observation ──
drop policy if exists obs_children_all on public.observation_children;
create policy obs_children_all on public.observation_children
  for all using (
    exists (
      select 1 from public.observations o
       where o.id = observation_children.observation_id
         and public.is_program_member(o.program_id)
    )
  );

drop policy if exists obs_attachments_all on public.observation_attachments;
create policy obs_attachments_all on public.observation_attachments
  for all using (
    exists (
      select 1 from public.observations o
       where o.id = observation_attachments.observation_id
         and public.is_program_member(o.program_id)
    )
  );

drop policy if exists obs_domain_tags_all on public.observation_domain_tags;
create policy obs_domain_tags_all on public.observation_domain_tags
  for all using (
    exists (
      select 1 from public.observations o
       where o.id = observation_domain_tags.observation_id
         and public.is_program_member(o.program_id)
    )
  );

-- ── Standard program-scoped entity tables ──────────────────────────
-- Every table in this list has the same shape: a `program_id` FK
-- to public.programs and three policies (_select, _insert, _update)
-- that all gate on "user is a member of the row's program."
-- Loop over the list and rewrite each one to call is_program_member.
do $$
declare
  t text;
  tables text[] := array[
    'groups',
    'rooms',
    'roles',
    'parents',
    'children',
    'adults',
    'vehicles',
    'trips',
    'activity_library',
    'lesson_sequences',
    'themes',
    'schedule_templates',
    'schedule_entries',
    'parent_concern_notes',
    'form_submissions'
  ];
begin
  foreach t in array tables loop
    if exists (
      select 1 from information_schema.tables
       where table_schema='public' and table_name=t
    ) then
      execute format('drop policy if exists %I_select on public.%I', t, t);
      execute format(
        'create policy %I_select on public.%I '
        'for select using (program_id is not null '
        'and public.is_program_member(%I.program_id))',
        t, t, t
      );
      execute format('drop policy if exists %I_insert on public.%I', t, t);
      execute format(
        'create policy %I_insert on public.%I '
        'for insert with check (program_id is not null '
        'and public.is_program_member(%I.program_id))',
        t, t, t
      );
      execute format('drop policy if exists %I_update on public.%I', t, t);
      execute format(
        'create policy %I_update on public.%I '
        'for update using (program_id is not null '
        'and public.is_program_member(%I.program_id))',
        t, t, t
      );
    end if;
  end loop;
end $$;

-- ── Cascade tables — scope through their parent's program ──────────
-- Every (cascade_table, parent_table, fk_col) triple gets one
-- `<cascade>_all` policy that checks membership via the parent.
do $$
declare
  rec record;
begin
  for rec in
    select * from (values
      ('parent_children',              'parents',             'parent_id'),
      ('child_schedule_overrides',     'children',            'child_id'),
      ('attendance',                   'children',            'child_id'),
      ('adult_availability',           'adults',              'adult_id'),
      ('adult_day_blocks',             'adults',              'adult_id'),
      ('trip_groups',                  'trips',               'trip_id'),
      ('activity_library_domain_tags', 'activity_library',    'library_item_id'),
      ('activity_library_usages',      'activity_library',    'library_item_id'),
      ('lesson_sequence_items',        'lesson_sequences',    'sequence_id'),
      ('template_groups',              'schedule_templates',  'template_id'),
      ('entry_groups',                 'schedule_entries',    'entry_id'),
      ('parent_concern_children',      'parent_concern_notes','concern_id')
    ) as t(cascade_table, parent_table, fk_col)
  loop
    if exists (
      select 1 from information_schema.tables
       where table_schema='public' and table_name=rec.cascade_table
    ) then
      execute format('drop policy if exists %I_all on public.%I',
                     rec.cascade_table, rec.cascade_table);
      execute format(
        'create policy %I_all on public.%I '
        'for all using ( exists ( '
        '  select 1 from public.%I p '
        '   where p.id = %I.%I '
        '     and public.is_program_member(p.program_id)) )',
        rec.cascade_table, rec.cascade_table,
        rec.parent_table,
        rec.cascade_table, rec.fk_col
      );
    end if;
  end loop;
end $$;

-- ── adult_role_blocks + overrides — already use is_program_member,
-- re-state for completeness so the migration leaves a consistent
-- shape across every cascade table.
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

-- ── Storage policies (db_backups + media buckets) ──────────────────
drop policy if exists "db_backups_select" on storage.objects;
create policy "db_backups_select" on storage.objects
  for select using (
    bucket_id = 'db_backups'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "db_backups_insert" on storage.objects;
create policy "db_backups_insert" on storage.objects
  for insert with check (
    bucket_id = 'db_backups'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "db_backups_update" on storage.objects;
create policy "db_backups_update" on storage.objects
  for update using (
    bucket_id = 'db_backups'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "db_backups_delete" on storage.objects;
create policy "db_backups_delete" on storage.objects
  for delete using (
    bucket_id = 'db_backups'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "media_select" on storage.objects;
create policy "media_select" on storage.objects
  for select using (
    bucket_id = 'media'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "media_insert" on storage.objects;
create policy "media_insert" on storage.objects
  for insert with check (
    bucket_id = 'media'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "media_update" on storage.objects;
create policy "media_update" on storage.objects
  for update using (
    bucket_id = 'media'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "media_delete" on storage.objects;
create policy "media_delete" on storage.objects
  for delete using (
    bucket_id = 'media'
    and public.is_program_member((storage.foldername(name))[1])
  );

-- =====================================================================
-- Part 3 — Foreign-key indexes
-- =====================================================================
--
-- An FK column without a covering index forces sequential scans on
-- DELETE / UPDATE of the parent and on any join that filters by the
-- FK. Postgres's planner can use the *leftmost* column of a composite
-- PK as an index for FK ops, but the second column (e.g. `child_id`
-- in `(parent_id, child_id)` PK) needs its own index.
--
-- Each index is keyed on the FK column alone — sufficient for FK
-- maintenance and the typical "find rows in cascade C that point to
-- parent row P" lookup.
--
-- Defensive guard: wraps each `create index` in a `to_regclass`
-- existence check. Cloud schemas at different points in the migration
-- ladder can be missing tables this migration would otherwise touch
-- (e.g. fresh projects that haven't run the per-feature 0005 slice
-- table yet). The guards turn "table missing → migration fails" into
-- a no-op so this hardening pass is safe to run anywhere.

do $$
declare
  rec record;
begin
  for rec in
    select * from (values
      ('programs',                     'idx_programs_created_by',                'created_by'),
      ('parent_children',              'idx_parent_children_child',              'child_id'),
      ('trip_groups',                  'idx_trip_groups_group',                  'group_id'),
      ('template_groups',              'idx_template_groups_group',              'group_id'),
      ('entry_groups',                 'idx_entry_groups_group',                 'group_id'),
      ('parent_concern_children',      'idx_parent_concern_children_child',      'child_id'),
      ('observation_children',         'idx_observation_children_child',         'child_id'),
      ('adult_role_blocks',            'idx_adult_role_blocks_group',            'group_id'),
      ('adult_role_blocks',            'idx_adult_role_blocks_program',          'program_id'),
      ('adult_role_block_overrides',   'idx_adult_role_block_overrides_group',   'group_id'),
      ('adult_role_block_overrides',   'idx_adult_role_block_overrides_program', 'program_id'),
      ('program_invites',              'idx_program_invites_created_by',         'created_by'),
      ('program_invites',              'idx_program_invites_accepted_by',        'accepted_by')
    ) as t(table_name, index_name, fk_col)
  loop
    if to_regclass(format('public.%I', rec.table_name)) is not null then
      execute format(
        'create index if not exists %I on public.%I (%I)',
        rec.index_name, rec.table_name, rec.fk_col
      );
    end if;
  end loop;
end $$;
