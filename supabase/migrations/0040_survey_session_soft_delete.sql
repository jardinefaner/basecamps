-- Soft-delete on `survey_sessions`.
--
-- Sessions had only hard-delete via FK cascade from the parent
-- survey. Teachers needed to remove a mistaken kiosk run (kid
-- pressed through twice, a session started by accident, etc)
-- without losing the parent survey or any other session.
--
-- Mirrors the soft-delete pattern already in place on the parent
-- `surveys` table: nullable timestamptz, row stays in the DB,
-- the results sheet filters `where deleted_at is null`.
--
-- Drift parity: schema v66.

alter table public.survey_sessions
  add column if not exists deleted_at timestamptz;

-- Useful when a teacher restores a session (clear deleted_at) or
-- when reporting wants to exclude soft-deleted runs.
create index if not exists survey_sessions_program_deleted_idx
  on public.survey_sessions (program_id, deleted_at)
  where deleted_at is null;
