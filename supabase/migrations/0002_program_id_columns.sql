-- v42 mirror: program_id on every entity table.
--
-- Drift schema v42 stamps every entity table with a nullable
-- program_id and a one-shot backfill on first sign-in. The cloud
-- side mirrors that here so when Slice C (per-table sync) lights up,
-- the columns and indexes already exist server-side.
--
-- Notes:
--  - Same scope as the Drift migration. Joins / cascade-children
--    tables are intentionally untouched (TripGroups, TemplateGroups,
--    EntryGroups, ParentChildren, ObservationChildren / -Attachments
--    / -DomainTags, AdultAvailability, AdultDayBlocks,
--    ChildScheduleOverrides, Attendance, Captures / CaptureChildren,
--    ActivityLibraryDomainTags / -Usages, LessonSequenceItems,
--    ParentConcernChildren). Their parents already carry program_id;
--    they cascade.
--  - Tables that don't exist in cloud yet (because Slice C hasn't
--    run for them) are still listed — `add column if not exists` is
--    a no-op when the table itself doesn't exist (the statement
--    fails silently inside `do $$ ... $$` blocks).
--    For now we keep this conservative: only add the column when the
--    table exists. Slice C migrations create the tables and re-run
--    this column add for safety.

do $$
declare
  t text;
  tables text[] := array[
    'children',
    'groups',
    'vehicles',
    'trips',
    'adults',
    'roles',
    'parents',
    'rooms',
    'schedule_templates',
    'schedule_entries',
    'observations',
    'activity_library',
    'lesson_sequences',
    'themes',
    'parent_concern_notes',
    'form_submissions'
  ];
begin
  foreach t in array tables loop
    -- Only act when the table actually exists in `public`. Slice C
    -- creates them one at a time; this migration is forward-
    -- compatible with the partial state.
    if exists (
      select 1 from information_schema.tables
      where table_schema = 'public' and table_name = t
    ) then
      execute format(
        'alter table public.%I add column if not exists program_id text '
        'references public.programs(id) on delete cascade',
        t
      );
      execute format(
        'create index if not exists idx_%I_program on public.%I (program_id)',
        t, t
      );
    end if;
  end loop;
end $$;
