-- Foreign-key + frequent-query indexes surfaced by the database
-- audit. Postgres doesn't auto-index FKs, and several heavy
-- screens were full-table-scanning every render. All partial
-- where the FK is nullable (most rows are typically null), so
-- the indexes stay small.
--
-- Idempotent (`if not exists`).

-- ---------------------------------------------------------------
-- observations: FKs + the most common query (by date for Today)
-- ---------------------------------------------------------------

create index if not exists idx_observations_child
  on public.observations (child_id)
  where child_id is not null;

create index if not exists idx_observations_group
  on public.observations (group_id)
  where group_id is not null;

create index if not exists idx_observations_trip
  on public.observations (trip_id)
  where trip_id is not null;

create index if not exists idx_observations_room
  on public.observations (room_id)
  where room_id is not null;

create index if not exists idx_observations_activity_date
  on public.observations (activity_date)
  where activity_date is not null;

-- ---------------------------------------------------------------
-- attendance: by-date queries (Today screen)
-- ---------------------------------------------------------------

create index if not exists idx_attendance_date
  on public.attendance (date);

-- ---------------------------------------------------------------
-- schedule_templates: FKs that drive lookup sheets
-- ---------------------------------------------------------------

create index if not exists idx_schedule_templates_group
  on public.schedule_templates (group_id)
  where group_id is not null;

create index if not exists idx_schedule_templates_adult
  on public.schedule_templates (adult_id)
  where adult_id is not null;

create index if not exists idx_schedule_templates_room
  on public.schedule_templates (room_id)
  where room_id is not null;

-- ---------------------------------------------------------------
-- schedule_entries: date range + every FK that's user-pivotable
-- ---------------------------------------------------------------

create index if not exists idx_schedule_entries_date
  on public.schedule_entries (date);

create index if not exists idx_schedule_entries_overrides_template
  on public.schedule_entries (overrides_template_id)
  where overrides_template_id is not null;

create index if not exists idx_schedule_entries_source_trip
  on public.schedule_entries (source_trip_id)
  where source_trip_id is not null;

create index if not exists idx_schedule_entries_group
  on public.schedule_entries (group_id)
  where group_id is not null;

create index if not exists idx_schedule_entries_adult
  on public.schedule_entries (adult_id)
  where adult_id is not null;

create index if not exists idx_schedule_entries_room
  on public.schedule_entries (room_id)
  where room_id is not null;

-- ---------------------------------------------------------------
-- form_submissions: FKs for context links + the dashboard query
-- ---------------------------------------------------------------

create index if not exists idx_form_submissions_child
  on public.form_submissions (child_id)
  where child_id is not null;

create index if not exists idx_form_submissions_group
  on public.form_submissions (group_id)
  where group_id is not null;

create index if not exists idx_form_submissions_trip
  on public.form_submissions (trip_id)
  where trip_id is not null;

create index if not exists idx_form_submissions_parent
  on public.form_submissions (parent_submission_id)
  where parent_submission_id is not null;

-- (form_type, status) drives the "everything in draft" / "active
-- monitorings" Today scans. Composite so both prefixes work.
create index if not exists idx_form_submissions_type_status
  on public.form_submissions (form_type, status);

-- review_due_at drives the "anything overdue right now?" flag in
-- todayReviewDueProvider — currently a seq-scan filtered by
-- timestamp.
create index if not exists idx_form_submissions_review_due
  on public.form_submissions (review_due_at)
  where review_due_at is not null;

-- ---------------------------------------------------------------
-- child_schedule_overrides: composite (child_id, date) — the
-- exact lookup the lateness-flags pass does per render.
-- ---------------------------------------------------------------

create index if not exists idx_child_schedule_overrides_child_date
  on public.child_schedule_overrides (child_id, date);

-- ---------------------------------------------------------------
-- lesson_sequence_items: reverse lookup "which sequence references
-- this library item?"
-- ---------------------------------------------------------------

create index if not exists idx_lesson_sequence_items_library
  on public.lesson_sequence_items (library_item_id)
  where library_item_id is not null;
