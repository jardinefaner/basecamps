-- The smoking-gun fix for the persistent 42501 on program create.
--
-- Diagnosis (after `whoami()` / diagnostics screen confirmed every
-- identity layer was matching end-to-end):
--   1. INSERT into `programs` runs.
--   2. WITH CHECK `auth.uid() = created_by` passes — proven via
--      diagnostics, both sides are the same uuid.
--   3. PostgREST then SELECT-backs the inserted row to return it
--      to the client (default "return=representation" behavior).
--   4. The SELECT-back evaluates `programs_select`, which gates on
--      `is_program_member(programs.id)`.
--   5. The user just inserted the program — their `program_members`
--      row hasn't been written YET (it's the next call in
--      `createAndSwitchProgram`). So they aren't a member.
--   6. SELECT-back returns zero rows. PostgREST reports this as
--      "new row violates row-level security policy for table
--      'programs'" — same wire error code (42501), confusingly
--      phrased, but actually a SELECT-policy issue, not a WITH
--      CHECK violation.
--
-- Fix: let the creator always SELECT their own program, even
-- before the membership row is in place. Once membership lands
-- (one line later in the create flow), the existing
-- `is_program_member` arm also satisfies the policy. The two
-- arms compose cleanly via `OR`.
--
-- Idempotent (drop + create).

drop policy if exists programs_select on public.programs;
create policy programs_select on public.programs
  for select using (
    public.is_program_member(programs.id)
    or programs.created_by = auth.uid()
  );
