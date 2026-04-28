-- Realtime UPDATEs were silently dropping for filtered channels.
--
-- Why: Postgres' default REPLICA IDENTITY (= primary key) only
-- exposes the PK columns to the WAL stream. Supabase Realtime's
-- server-side filter (`program_id = '<id>'`) then has no
-- `program_id` to match against on UPDATEs — only the PK shows
-- up. The realtime worker silently drops the event, the joiner's
-- subscription never fires, and changes feel "not live" even
-- though the rows are landing in cloud correctly.
--
-- Fix: set REPLICA IDENTITY FULL on every program-scoped table
-- (and the cascade tables that scope through a parent's
-- program_id). With FULL, the WAL records include every column,
-- so the filter can match `program_id` and the realtime channel
-- delivers UPDATEs cleanly. INSERTs were unaffected (the new
-- record is included in WAL regardless of replica identity), so
-- this fix specifically unblocks live UPDATE / DELETE delivery.
--
-- Cost: tiny per-write WAL overhead (each row's full column set
-- gets written instead of just the PK on UPDATE). For programs-
-- scale data — at most thousands of rows total per program —
-- this is invisible. Worth it for the "live" expectation.
--
-- Idempotent: alter table ... replica identity is no-op when
-- already set to the requested value.

-- Generated with a DO block so adding a new entity table is one
-- line in the array, not a copy-pasted ALTER. Mirrors the same
-- table list as 0007_enable_realtime.sql.

do $$
declare
  t text;
  tbls text[] := array[
    -- Tier 1 / 2 / 3 entity tables (have program_id directly)
    'observations',
    'observation_children',
    'observation_attachments',
    'observation_domain_tags',
    'groups',
    'rooms',
    'roles',
    'parents',
    'parent_children',
    'children',
    'child_schedule_overrides',
    'attendance',
    'adults',
    'adult_availability',
    'adult_day_blocks',
    'vehicles',
    'trips',
    'trip_groups',
    'activity_library',
    'activity_library_domain_tags',
    'activity_library_usages',
    'lesson_sequences',
    'lesson_sequence_items',
    'themes',
    'schedule_templates',
    'template_groups',
    'schedule_entries',
    'entry_groups',
    'form_submissions',
    -- Programs membership graph — joiners need to see role
    -- changes / kicks instantly.
    'programs',
    'program_members'
  ];
begin
  foreach t in array tbls loop
    -- to_regclass returns null for missing tables (e.g.
    -- parent_concern_notes after the v45 cleanup) — guard with
    -- IF FOUND so a missing legacy table doesn't block the loop.
    if to_regclass('public.' || t) is not null then
      execute format(
        'alter table public.%I replica identity full',
        t
      );
    end if;
  end loop;
end $$;
