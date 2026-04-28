-- The creator of a program should always be able to update and
-- delete it, even when the membership graph is in flux. Same
-- defense-in-depth principle as 0015: a creator's auth identity
-- alone should be enough to manage what they made.
--
-- Without this, a brand-new program can land in a state where:
--   * The `programs` row exists with `created_by = me`.
--   * The matching `program_members` row never made it (the
--     chronic 42501 cascade we just untangled blocked the
--     follow-up insert).
--   * `programs_update` / `programs_delete` are gated on
--     `is_program_admin(id)` — admin = a `program_members` row
--     with role='admin'.
--   * Without that membership row, the user can't update or
--     delete the program they themselves created. They're stuck.
--
-- Fix: allow either the program admin OR the original creator.
-- Once membership lands the admin arm passes too; both compose
-- via OR. Creator-arm is cheap, doesn't open new attack
-- surface (only the row's own creator gets a pass), and
-- restores the natural mental model.
--
-- Idempotent: drop + create.

drop policy if exists programs_update on public.programs;
create policy programs_update on public.programs
  for update using (
    public.is_program_admin(programs.id)
    or programs.created_by = auth.uid()
  );

drop policy if exists programs_delete on public.programs;
create policy programs_delete on public.programs
  for delete using (
    public.is_program_admin(programs.id)
    or programs.created_by = auth.uid()
  );

-- Drop the legacy backup-cleanup trigger (introduced in 0003,
-- retired with the BackupCard in commit 549b2dc). It tries to
-- DELETE FROM storage.objects directly, which newer Supabase
-- versions reject with:
--   "Direct deletion from storage tables is not allowed.
--    Use the Storage API instead."
-- Symptom: program delete fails with 42501 even when the user
-- has the right RLS permissions on programs itself — the
-- failure comes from the AFTER DELETE trigger.
--
-- We don't need the cleanup anyway: the BackupCard / snapshot
-- feature is gone. Live sync per-row replaces it; no
-- per-program JSON blob to clean up. Drop the trigger AND the
-- function so neither remains as residue.
drop trigger if exists programs_cleanup_backup on public.programs;
drop function if exists public.cleanup_program_backup();
