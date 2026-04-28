-- Curriculum v47: phase, per-week color, engine notes on
-- lesson_sequences. Mirrors the Drift v47 onUpgrade in
-- lib/database/database.dart.
--
-- Why: lets the curriculum view render phase headers (e.g.
-- "ALL ABOUT ME" spanning weeks 1–2), give each week its own
-- accent color (gradient inside a phase), and surface a
-- behind-the-scenes "engine notes" pane with the curriculum
-- author's pedagogical commentary.
--
-- All additive nullable columns. No row-level changes; existing
-- sequences keep working unchanged. Idempotent (IF NOT EXISTS)
-- so re-running is safe.

alter table public.lesson_sequences
  add column if not exists phase text;

alter table public.lesson_sequences
  add column if not exists color_hex text;

alter table public.lesson_sequences
  add column if not exists engine_notes text;
