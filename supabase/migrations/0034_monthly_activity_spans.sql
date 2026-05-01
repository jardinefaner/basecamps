-- v57: monthly plan multi-day spans (Slice 3).
--
-- A "span" is one logical activity that runs across N consecutive
-- days (e.g. a 3-day book read-aloud arc). All rows in a span share
-- a span_id; span_position orders them within the span (0 = head,
-- 1+ = continuation days). Each continuation row is its own
-- monthly_activities row living in its own (group, date) cell —
-- so the existing per-cell queries, RLS, sync, and indexes keep
-- working without surgery.
--
-- The head row carries the activity's full content (title,
-- description, steps, materials). Continuation rows MAY carry
-- per-day specifics (the AI continuity prompt fills these); UI
-- renders a "continued" pill that links back to the head when the
-- continuation row's title is empty.
--
-- Mirrors Drift v57 in lib/database/database.dart.

alter table public.monthly_activities
  add column if not exists span_id text;

alter table public.monthly_activities
  add column if not exists span_position integer not null default 0;

-- Index on span_id for fetch-by-span queries (the formatted sheet
-- lists all days in the span; the materials aggregator dedupes by
-- span_id; the trim path looks up continuation rows). Partial on
-- non-null because most activities are single-day, so indexing
-- nulls is wasted space.
create index if not exists idx_monthly_activities_span
  on public.monthly_activities (program_id, span_id, span_position)
  where span_id is not null and deleted_at is null;
