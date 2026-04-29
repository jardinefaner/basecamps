-- Re-restore the creator OR-arms on `programs` policies that 0020
-- accidentally stripped, and re-drop the legacy
-- `cleanup_program_backup` function that 0020 wrongly re-created.
--
-- Background:
--   * 0015 added `or programs.created_by = auth.uid()` to
--     `programs_select` so the creator can SELECT-back their
--     freshly-inserted program row *before* their membership row
--     lands one statement later. Without it, PostgREST's default
--     `return=representation` SELECT after INSERT returns zero
--     rows and surfaces as `42501 — new row violates RLS`. (Wire
--     code is misleading; it's actually a SELECT-policy issue.)
--   * 0016 added the same OR-arm to `programs_update` and
--     `programs_delete` so a creator who's stuck without a
--     membership row can still rename / delete their own program.
--   * 0016 also dropped the `cleanup_program_backup` trigger AND
--     function, because newer Supabase rejects direct DELETE
--     from storage.objects ("Use the Storage API instead.").
--
-- The 0020 hardening pass rewrote those three policies and folded
-- the cleanup function back in (with a search_path setting + revoke
-- as part of the search_path lint sweep). It dropped both:
--   1. the creator OR-arms — programs_insert still passes
--      WITH CHECK, but the SELECT-back fails the creator who
--      isn't a member yet, so program-create errors with 42501.
--   2. the function-removal — cleanup_program_backup exists again
--      but isn't attached to any trigger, so it's just dead code.
--
-- This migration restores 0015 + 0016's intent on top of 0020's
-- search_path-hardened helpers. Idempotent (drop + create / drop
-- if exists).

drop policy if exists programs_select on public.programs;
create policy programs_select on public.programs
  for select using (
    public.is_program_member(programs.id)
    or programs.created_by = (select auth.uid())
  );

drop policy if exists programs_update on public.programs;
create policy programs_update on public.programs
  for update using (
    public.is_program_admin(programs.id)
    or programs.created_by = (select auth.uid())
  );

drop policy if exists programs_delete on public.programs;
create policy programs_delete on public.programs
  for delete using (
    public.is_program_admin(programs.id)
    or programs.created_by = (select auth.uid())
  );

-- And: drop the function 0020 mistakenly recreated. The trigger was
-- already dropped in 0016 and not re-attached in 0020, so the
-- function was orphan dead code; this just cleans up.
drop function if exists public.cleanup_program_backup();
