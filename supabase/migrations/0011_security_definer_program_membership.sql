-- Hot fix (2026-04-28): break the RLS infinite-recursion in
-- `program_members` policies, plus the same recursive shape that
-- leaked into every entity / cascade / storage policy that joined
-- to program_members.
--
-- Symptom: "Sync now" failed with
-- `PostgrestException(message: infinite recursion detected in policy
--  for relation "program_members", code: 42P17)` and "Back up now"
-- failed with `StorageException(... DatabaseInvalidObjectDefinition)`.
--
-- Root cause: every policy did
--   exists (select 1 from public.program_members m where ...)
-- inline. When SELECT-on-program_members is itself gated by an RLS
-- policy that subqueries program_members, every reference triggers
-- recursive policy evaluation. Postgres' planner can't prove the
-- recursion will terminate and bails with 42P17.
--
-- Fix: extract the membership check into two SECURITY DEFINER
-- helper functions. SECURITY DEFINER runs with the function
-- owner's privileges and bypasses RLS for the queries inside it,
-- so the membership lookup terminates without re-firing any policy.
-- Every policy that referenced program_members is rewritten to call
-- the helper instead.
--
-- The helpers are STABLE (deterministic inside a single statement)
-- and explicitly not LEAKPROOF — Postgres can still optimize the
-- planner's policy evaluation but won't push them through other
-- security boundaries. Marking them STABLE lets Postgres cache the
-- result inside a query.
--
-- Idempotent: every CREATE is preceded by a DROP IF EXISTS, so this
-- migration can be re-applied if it's edited later.

-- =====================================================================
-- Helpers
-- =====================================================================

create or replace function public.is_program_member(p_program_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.program_members m
     where m.program_id = p_program_id
       and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_program_admin(p_program_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.program_members m
     where m.program_id = p_program_id
       and m.user_id = auth.uid()
       and m.role = 'admin'
  );
$$;

-- Allow authenticated callers to use the helpers from inside their
-- own queries (e.g. an explicit `select is_program_admin(:id)` from
-- the app). RLS won't re-enter inside the SECURITY DEFINER body.
grant execute on function public.is_program_member(text) to authenticated;
grant execute on function public.is_program_admin(text)  to authenticated;

-- =====================================================================
-- programs (was 0001) — rewritten to use is_program_*
-- =====================================================================

drop policy if exists programs_select on public.programs;
create policy programs_select on public.programs
  for select using ( public.is_program_member(programs.id) );

-- INSERT policy unchanged from 0001 — references auth.uid() only,
-- not program_members, so no recursion. Re-stated here so this
-- migration is self-describing for future readers.
drop policy if exists programs_insert on public.programs;
create policy programs_insert on public.programs
  for insert with check (auth.uid() = created_by);

drop policy if exists programs_update on public.programs;
create policy programs_update on public.programs
  for update using ( public.is_program_admin(programs.id) );

drop policy if exists programs_delete on public.programs;
create policy programs_delete on public.programs
  for delete using ( public.is_program_admin(programs.id) );

-- =====================================================================
-- program_members (was 0001) — the recursion source. The new
-- policies still allow a user to read their own row (so the
-- bootstrap and the cross-device hydrate find their memberships)
-- without doing any inline subquery against program_members.
-- =====================================================================

drop policy if exists program_members_select on public.program_members;
create policy program_members_select on public.program_members
  for select using (
    user_id = auth.uid()
    or public.is_program_admin(program_members.program_id)
  );

drop policy if exists program_members_insert on public.program_members;
create policy program_members_insert on public.program_members
  for insert with check (
    -- Admin of the program adding someone (the helper bypasses RLS
    -- so this no longer recurses).
    public.is_program_admin(program_members.program_id)
    -- OR: bootstrap case — user inserting their own first row in
    -- a program they just created. Same as 0001 except the inner
    -- check on program_members (used to confirm "no rows yet")
    -- is gone; the `created_by = auth.uid()` clause on the program
    -- already gates this case to the program creator.
    or (
      user_id = auth.uid()
      and exists (
        select 1 from public.programs p
        where p.id = program_members.program_id
          and p.created_by = auth.uid()
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
    user_id = auth.uid()
    or public.is_program_admin(program_members.program_id)
  );

-- =====================================================================
-- Storage: db_backups bucket (was 0003)
-- =====================================================================

drop policy if exists "db_backups_select" on storage.objects;
create policy "db_backups_select" on storage.objects
  for select
  using (
    bucket_id = 'db_backups'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "db_backups_insert" on storage.objects;
create policy "db_backups_insert" on storage.objects
  for insert
  with check (
    bucket_id = 'db_backups'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "db_backups_update" on storage.objects;
create policy "db_backups_update" on storage.objects
  for update
  using (
    bucket_id = 'db_backups'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "db_backups_delete" on storage.objects;
create policy "db_backups_delete" on storage.objects
  for delete
  using (
    bucket_id = 'db_backups'
    and public.is_program_member((storage.foldername(name))[1])
  );

-- =====================================================================
-- Storage: media bucket (was 0008)
-- =====================================================================

drop policy if exists "media_select" on storage.objects;
create policy "media_select" on storage.objects
  for select
  using (
    bucket_id = 'media'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "media_insert" on storage.objects;
create policy "media_insert" on storage.objects
  for insert
  with check (
    bucket_id = 'media'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "media_update" on storage.objects;
create policy "media_update" on storage.objects
  for update
  using (
    bucket_id = 'media'
    and public.is_program_member((storage.foldername(name))[1])
  );

drop policy if exists "media_delete" on storage.objects;
create policy "media_delete" on storage.objects
  for delete
  using (
    bucket_id = 'media'
    and public.is_program_member((storage.foldername(name))[1])
  );

-- =====================================================================
-- observations + cascades (was 0004)
-- =====================================================================

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

drop policy if exists obs_children_all on public.observation_children;
create policy obs_children_all on public.observation_children
  for all using (
    exists (
      select 1 from public.observations o
       where o.id = observation_children.observation_id
         and o.program_id is not null
         and public.is_program_member(o.program_id)
    )
  );

drop policy if exists obs_attachments_all on public.observation_attachments;
create policy obs_attachments_all on public.observation_attachments
  for all using (
    exists (
      select 1 from public.observations o
       where o.id = observation_attachments.observation_id
         and o.program_id is not null
         and public.is_program_member(o.program_id)
    )
  );

drop policy if exists obs_domain_tags_all on public.observation_domain_tags;
create policy obs_domain_tags_all on public.observation_domain_tags
  for all using (
    exists (
      select 1 from public.observations o
       where o.id = observation_domain_tags.observation_id
         and o.program_id is not null
         and public.is_program_member(o.program_id)
    )
  );

-- =====================================================================
-- Entity tables (was 0005) — uniform 3-policy block per table.
-- Generated via PL/pgSQL DO so the rewrite stays maintainable;
-- adding a new entity table later just appends a name to the array.
-- =====================================================================

do $$
declare
  t text;
  entity_tables text[] := array[
    'groups', 'rooms', 'roles', 'parents', 'children', 'adults',
    'vehicles', 'trips', 'activity_library', 'lesson_sequences',
    'themes', 'schedule_templates', 'schedule_entries',
    'form_submissions'
  ];
begin
  foreach t in array entity_tables loop
    execute format(
      'drop policy if exists %1$I_select on public.%1$I; '
      'create policy %1$I_select on public.%1$I '
      '  for select using ( '
      '    program_id is not null '
      '    and public.is_program_member(%1$I.program_id) '
      '  )',
      t
    );
    execute format(
      'drop policy if exists %1$I_insert on public.%1$I; '
      'create policy %1$I_insert on public.%1$I '
      '  for insert with check ( '
      '    program_id is not null '
      '    and public.is_program_member(%1$I.program_id) '
      '  )',
      t
    );
    execute format(
      'drop policy if exists %1$I_update on public.%1$I; '
      'create policy %1$I_update on public.%1$I '
      '  for update using ( '
      '    program_id is not null '
      '    and public.is_program_member(%1$I.program_id) '
      '  )',
      t
    );
  end loop;
end $$;

-- The legacy parent_concern_notes table was dropped in 0009 but
-- some installs may still have its policies if the drop happened
-- mid-migration. DROP POLICY IF EXISTS is harmless when the table
-- itself is gone (Postgres treats the policies as already dropped
-- with the table). Skip it.

-- =====================================================================
-- Cascade tables (was 0005) — single ALL policy per table, joined
-- to its parent entity. Each parent's program_id check now goes
-- through is_program_member.
-- =====================================================================

drop policy if exists parent_children_all on public.parent_children;
create policy parent_children_all on public.parent_children
  for all using (
    exists (
      select 1 from public.parents p
       where p.id = parent_children.parent_id
         and public.is_program_member(p.program_id)
    )
  );

drop policy if exists child_schedule_overrides_all on public.child_schedule_overrides;
create policy child_schedule_overrides_all on public.child_schedule_overrides
  for all using (
    exists (
      select 1 from public.children c
       where c.id = child_schedule_overrides.child_id
         and public.is_program_member(c.program_id)
    )
  );

drop policy if exists attendance_all on public.attendance;
create policy attendance_all on public.attendance
  for all using (
    exists (
      select 1 from public.children c
       where c.id = attendance.child_id
         and public.is_program_member(c.program_id)
    )
  );

drop policy if exists adult_availability_all on public.adult_availability;
create policy adult_availability_all on public.adult_availability
  for all using (
    exists (
      select 1 from public.adults a
       where a.id = adult_availability.adult_id
         and public.is_program_member(a.program_id)
    )
  );

drop policy if exists adult_day_blocks_all on public.adult_day_blocks;
create policy adult_day_blocks_all on public.adult_day_blocks
  for all using (
    exists (
      select 1 from public.adults a
       where a.id = adult_day_blocks.adult_id
         and public.is_program_member(a.program_id)
    )
  );

drop policy if exists trip_groups_all on public.trip_groups;
create policy trip_groups_all on public.trip_groups
  for all using (
    exists (
      select 1 from public.trips t
       where t.id = trip_groups.trip_id
         and public.is_program_member(t.program_id)
    )
  );

drop policy if exists activity_library_domain_tags_all on public.activity_library_domain_tags;
create policy activity_library_domain_tags_all on public.activity_library_domain_tags
  for all using (
    exists (
      select 1 from public.activity_library a
       where a.id = activity_library_domain_tags.library_item_id
         and public.is_program_member(a.program_id)
    )
  );

drop policy if exists activity_library_usages_all on public.activity_library_usages;
create policy activity_library_usages_all on public.activity_library_usages
  for all using (
    exists (
      select 1 from public.activity_library a
       where a.id = activity_library_usages.library_item_id
         and public.is_program_member(a.program_id)
    )
  );

drop policy if exists lesson_sequence_items_all on public.lesson_sequence_items;
create policy lesson_sequence_items_all on public.lesson_sequence_items
  for all using (
    exists (
      select 1 from public.lesson_sequences s
       where s.id = lesson_sequence_items.sequence_id
         and public.is_program_member(s.program_id)
    )
  );

drop policy if exists template_groups_all on public.template_groups;
create policy template_groups_all on public.template_groups
  for all using (
    exists (
      select 1 from public.schedule_templates t
       where t.id = template_groups.template_id
         and public.is_program_member(t.program_id)
    )
  );

drop policy if exists entry_groups_all on public.entry_groups;
create policy entry_groups_all on public.entry_groups
  for all using (
    exists (
      select 1 from public.schedule_entries e
       where e.id = entry_groups.entry_id
         and public.is_program_member(e.program_id)
    )
  );

-- parent_concern_children was dropped with its parent in 0009.
-- Its policy is gone too — no rewrite needed.
