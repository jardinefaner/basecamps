-- 0042 — observation_children.metadata jsonb (future-proof per-child sidecar)
--
-- Why JSON sidecar over more typed columns: per-child extensions
-- (note, sentiment, skill codes, attachment links, captured_at) have
-- been requested but the product hasn't decided which to ship. A
-- single nullable JSON column lets the UI start writing fields the
-- moment a feature lands without further migrations — and the sync
-- engine already round-trips arbitrary cascade columns through the
-- generic upsert path, so no engine changes are required either.
--
-- The trade-off (no indexed queries on the JSON keys, no type
-- validation at the DB level) is acceptable because every report
-- today is observation-scoped, not child-scoped. When per-child
-- querying becomes a real need we can promote individual keys to
-- typed columns in a follow-up migration.
--
-- Heal-first pattern: in case 0004 didn't run on a project (fresh
-- bootstrap), create the table before the alter so the column add
-- can't fail with "relation does not exist."

create table if not exists public.observation_children (
  observation_id text not null
    references public.observations(id) on delete cascade,
  child_id text not null,
  created_at timestamptz not null default now(),
  primary key (observation_id, child_id)
);

alter table public.observation_children
  add column if not exists metadata jsonb;

-- No backfill: metadata stays NULL for every existing row. UI reads
-- a missing field as "not provided" and falls through to the
-- observation-level value (e.g. parent sentiment when no per-child
-- sentiment is set).

-- No new index. The JSON column is read as a sidecar on every join-
-- row pull (the engine SELECTs every column) — querying inside the
-- JSON is not a current use case.
