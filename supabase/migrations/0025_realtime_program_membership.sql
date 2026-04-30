-- Realtime + sync coverage for the program membership graph.
--
-- The original 0007_enable_realtime migration enrolled every
-- entity table in the `supabase_realtime` publication, but
-- skipped `programs`, `program_members`, and `program_invites`.
-- Combined with a client-side hydrate that filtered to
-- `eq('user_id', userId)`, the user-visible effect was: each
-- device only ever saw its own membership row, so the program
-- detail screen's members list rendered as just yourself
-- regardless of how many co-teachers were actually on the
-- program. ("I don't see members even though there's multiple.")
--
-- Migration 0017 already set REPLICA IDENTITY FULL on these
-- tables, and 0019 opened the SELECT RLS so peers can see each
-- other. The publication add was the missing piece. This
-- migration completes the trio. The client-side hydrate fix
-- (programs_repository.dart `hydrateCloudProgramsForUser`)
-- broadens the SELECT to `inFilter('program_id', programIds)`,
-- so on every periodic pull / foreground resume each device
-- now refreshes the full peer roster.
--
-- Idempotent: `alter publication … add table` errors if the
-- table is already enrolled, so we wrap each call in a DO
-- block that swallows the duplicate-object error code.

do $$
begin
  alter publication supabase_realtime add table public.programs;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.program_members;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.program_invites;
exception when duplicate_object then null;
end $$;
