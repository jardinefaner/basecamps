-- Curriculum arc additions (Slice A) — pair LessonSequences with a
-- Theme so the curriculum view can render a multi-week arc, give
-- each sequence a "core question" prompt, stamp every
-- LessonSequenceItem with a day-of-week + a `kind` discriminator,
-- and add an `age_variants` JSON blob to ActivityLibrary so a single
-- card can carry adjacent-age rewrites of summary / key points /
-- learning goals.
--
-- All additive nullable (or defaulted) columns. Existing rows keep
-- working: the curriculum view falls back to "free-floating" mode
-- when theme_id is null, daily/milestone gating is permissive when
-- day_of_week is null, and the age-scaling toggle no-ops when
-- age_variants is null.
--
-- Mirrors the Drift v46 migration in lib/database/database.dart.
-- Storage as TEXT (JSON) on age_variants matches Drift's TextColumn —
-- the Postgres side could also use jsonb, but TEXT keeps the column
-- shape symmetrical with the local DB and avoids a dialect-specific
-- serialization branch in the sync engine.

alter table public.lesson_sequences
  add column if not exists theme_id text
  references public.themes(id) on delete set null;

alter table public.lesson_sequences
  add column if not exists core_question text;

create index if not exists idx_lesson_sequences_theme
  on public.lesson_sequences (theme_id);

alter table public.lesson_sequence_items
  add column if not exists day_of_week integer;

alter table public.lesson_sequence_items
  add column if not exists kind text not null default 'daily';

create index if not exists idx_lesson_sequence_items_kind
  on public.lesson_sequence_items (sequence_id, kind);

alter table public.activity_library
  add column if not exists age_variants text;
