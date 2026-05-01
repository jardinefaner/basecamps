-- v53: groups.audience_age_label
--
-- Free-text age range attached to each group. Drives AI generation
-- context (so a "Toddlers" group gets 2-yr-old-appropriate steps
-- when a teacher hits ✨) and could later filter activity-library
-- picks by age. Free text by intent — teachers say "3-5 years",
-- "preschool", "toddlers", and the AI prompts pattern-match either.
-- Storing as text rather than min/max integers keeps every shape
-- the user might type round-trippable without parser ambiguity.
--
-- Additive nullable — existing groups stay untouched and reads keep
-- working. Sync travels through the standard generic push/pull
-- (groupsSpec doesn't filter columns), so the new field shuttles
-- between local Drift and cloud automatically.

alter table public.groups
  add column if not exists audience_age_label text;
