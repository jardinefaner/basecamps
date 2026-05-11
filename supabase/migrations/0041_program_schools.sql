-- Program-level partner schools list.
--
-- Until now schools lived on each survey row. A teacher creating
-- a new survey had to retype the same school list every time —
-- annoying for a program that always has the same kid cohort,
-- and prone to typos that splinter the data ("KIPP" vs "kipp").
--
-- Move the canonical list to the program itself. The survey kiosk's
-- pre-flight gate reads program.schools_json now; existing surveys
-- keep their per-survey schools list as a frozen snapshot so
-- historical sessions don't lose context.
--
-- Drift parity: schema v67.

alter table public.programs
  add column if not exists schools_json text not null default '[]';
