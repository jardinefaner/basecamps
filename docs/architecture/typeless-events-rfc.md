# RFC: Typeless events (deferred)

**Status:** parked. Captured here so the thinking doesn't evaporate
between conversations.

**Context:** the Command Center experiment (`/command`) proves that a
single LLM-routed input bar can dispatch to the right typed tool
(observation / calendar tile / late pickup). The natural follow-on
question: should we collapse the typed tables into a single generic
`events` table where the LLM is the runtime schema author?

This RFC argues we **shouldn't go fully typeless**, but we *should*
add a single `freeform_events` table for the genuinely typeless
slice — voice-dictated notes that don't have a clean home today.

---

## What "typeless" would look like

A single table:

```sql
create table events (
  id text primary key,
  program_id text not null references programs(id),
  kind text not null,           -- 'observation' | 'late_pickup' | ... | 'note'
  who_ids text[] not null default '{}',
  when_ timestamptz,
  where_ text,
  payload jsonb not null default '{}',
  notes text,
  author_user_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index idx_events_program_kind_when
  on events (program_id, kind, when_ desc);
create index idx_events_payload_gin
  on events using gin (payload jsonb_path_ops);
```

All current features become VIEWS:

```sql
create view late_pickups as
  select id, program_id, when_ as picked_up_at,
         (payload->>'child_id') as child_id,
         (payload->>'parent_name') as parent_name,
         (payload->>'reminder_card_given')::bool as reminder_card_given,
         notes
  from events where kind = 'late_pickup';
```

The LLM is the schema author at runtime — `payload` is whatever
fields the model emitted for this `kind`.

## Why I'm against going fully typeless

1. **Cross-cutting queries get HARDER, not easier.** "Show me
   everything about Phillip last month" is the canonical use case
   for typeless. But a `where 'phillip-id' = any(who_ids)` query
   doesn't beat an indexed JOIN through `observation_children` to
   `observations`. Postgres' GIN indexes on JSONB are good but not
   ergonomic, and they bloat fast.

2. **The LLM is the schema author at runtime sounds magical until
   you need to migrate.** When you add `reminder_card_returned: bool`
   three months in:
   - Typed: `ALTER TABLE`, default false, done.
   - Typeless: every old row is missing the field; the model has to
     learn it exists; queries that filter on it have to handle
     absence; Excel exports have inconsistent columns row-by-row.

3. **Validation gets worse.** `survey_responses.mood_value` must be
   `0..2`. Postgres enforces that with `check (mood_value between
   0 and 2)`. JSONB lets the LLM emit `mood_value: "kinda agree"`
   and you find out at query time.

4. **RLS gets more invasive.** Today, observation_children inherits
   RLS through observation_id → observations.program_id. With a
   typeless table the policy is on `events.program_id` — fine — but
   the cascading entity FKs (children, groups, etc.) lose their
   referential integrity unless we encode them as JSONB and lose
   the `references` constraint.

5. **The win you're chasing is achievable WITHOUT typeless.** A
   `unified_events` *view* over the typed tables gives you the
   cross-cutting reads. A single Command Center input gives you
   the unified create grammar. The data layer doesn't have to
   collapse for the UX layer to feel unified.

## Where typeless DOES win

There's a real category that suffers under typed tables: **freeform
voice notes that don't fit a fixed schema yet.** Today we shoehorn
those into `observations` with a domain of `OTHER` and a long
`note` text. That's lossy:
- "We had a fire drill at 2:30, took 4 minutes, the sunflowers were
  champs" — schedule event? observation? incident report?
- "Maya's mom called about the rash" — parent comm? observation?
- "Found Phillip's water bottle in the nature corner" — lost &
  found? note?

These are events with a `kind` we haven't designed a typed table for
*yet*. A `freeform_events` table accepts them now; if a `kind`
becomes a real, recurring shape, we promote it to its own typed
table and migrate.

## Recommendation: hybrid

1. **Keep typed tables** for everything with a stable shape:
   surveys, observations (the core notes), calendar tiles (when
   they graduate from lab), late pickups (when they graduate),
   attendance, schedule.

2. **Add a `freeform_events` table** for the genuinely typeless
   slice. JSONB payload, `kind` is free-text, no FKs to entities
   except the program. The Command Center's LLM router has a
   fourth intent (`note`) that lands here when no typed match
   wins.

3. **Add a `unified_events` view** — `union all` across every
   typed table + freeform_events, normalised to (id, kind, when,
   who, summary, source_table). Drives the Command Center feed,
   the "show me everything about X" query, and any cross-cutting
   report.

This gives us the win (one query for cross-cutting reads, one
inbox for any utterance) without paying the cost (lost
validation, harder migrations, RLS hairballs).

## Migration path if we ever flip to fully typeless

If, after a year of operating the hybrid, the typed tables haven't
earned their keep:

1. Add a `kind` column to every typed table (already 1:1 with
   table name).
2. Backfill `events` from each typed table via insert-from-select.
3. Drop the typed tables and replace each with a view.

The reverse path (starting typeless and trying to extract typed
tables later) is much harder — it requires schema-discovery
tooling against the JSONB blobs and then row-by-row migration.
Starting typed and adding typeless later is the cheaper option.

## Open questions

- **CSV export for typeless.** What columns? Probably a separate
  exporter per `kind` that knows the payload shape, OR an LLM-
  driven export ("give me a CSV of late pickups" → SQL).
- **Search across types.** Postgres FTS on `notes` + a generated
  text column from `payload` would give us ripgrep-on-events for
  free.
- **The Command Center feed today.** It's per-session and
  per-screen. The unified view above is what makes it persistent
  and cross-device.
