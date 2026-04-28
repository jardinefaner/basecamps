-- GIN index on form_submissions.data for cheap "filter by field"
-- queries across the polymorphic form table.
--
-- Why this matters: a single forms table holds many form_types
-- (vehicle_check, incident_report, behavior_monitoring, ...) with
-- different fields stashed in `data`. Without an index, queries
-- like "every incident_report with severity > 3" or "every form
-- referencing this child id from a JSON pointer field" do a full
-- table scan and re-parse `data::jsonb` for every row.
--
-- The cast-on-the-fly index lets Postgres answer those queries
-- via a JSON path lookup. Negligible insert overhead (jsonb parse
-- once on write); large read win when the table grows.
--
-- Does not require changing the column type from text — Postgres
-- builds the index over the casted expression.

create index if not exists idx_form_submissions_data_jsonb
  on public.form_submissions
  using gin ((data::jsonb));
