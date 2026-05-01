-- v58: persisted add-ons on monthly_activities.
--
-- The add-ons feature (read-aloud questions, discussion ladders,
-- closing reflections, etc. — see lib/features/ai/ai_activity_addons.dart)
-- previously dropped its generated content the moment the sheet
-- closed. Teachers were re-running the same generation every time
-- they opened a lesson plan. This migration backs the section with
-- a single JSON column on the activity row so once generated, an
-- add-on stays put.
--
-- Why a JSON blob (not a child table): an add-on payload is small
-- (a few labelled paragraphs); there's a known finite set of
-- specs (~22); and the access pattern is "load all add-ons for
-- this activity at once" — perfect fit for a column. The sync
-- engine pushes/pulls this column like every other text field
-- through the standard generic path.
--
-- Shape: { "<spec_id>": [{"heading": "...", "body": "..."}, ...] }
-- Spec ids are stable strings declared in addonSpecs[].id.
--
-- Mirrors Drift v58 in lib/database/database.dart.

alter table public.monthly_activities
  add column if not exists addons text;
