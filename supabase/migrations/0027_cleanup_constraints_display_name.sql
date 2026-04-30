-- Schema cleanup + safe constraint additions + member display
-- name. All low-risk, all additive (no drops or row-level data
-- transformations except a one-time `'adult'` → `'specialist'`
-- normalization for adult_role).
--
-- WHY each chunk:
--
-- 1. `program_members.display_name`
--    The members card on the Program detail screen rendered
--    "Teacher · 12345678" (literal UUID prefix) because nothing
--    cloud-side carried a human name. The bootstrap will start
--    populating this from `auth.users.raw_user_meta_data` on
--    every membership upsert. Existing rows backfill via the
--    `accept-invite` edge function next round of activity.
--
-- 2. CHECK constraints on enum-like text columns (NOT VALID).
--    Cloud rejects new garbage values without re-validating
--    existing data — safe to add even when older rows might
--    have legacy enum values. CHECK already exists on
--    `adult_role_blocks.kind` (0018); this generalizes the
--    pattern.
--
-- 3. `adults.adult_role`: Drift schema default is 'adult',
--    cloud default is 'adult', but the Dart enum stamps
--    'specialist' on every new insert. So existing rows are a
--    mix of 'adult' (cloud-default-only inserts, legacy) and
--    'specialist' (new app inserts). `AdultRole.fromDb` already
--    maps 'adult' → AdultRole.specialist as a fallback, so they
--    behave identically. Normalize the storage so the CHECK can
--    be tight.
--
-- 4. `adult_role_block_overrides.date` is currently `date`
--    cloud-side while every other "date-only" column in the
--    schema (`trips.date`, `attendance.date`,
--    `child_schedule_overrides.date`, `schedule_entries.date`)
--    is `timestamptz`. Promoting it removes a near-midnight TZ
--    inconsistency the engine has to work around.
--
-- 5. `parent_children` lacks `updated_at` + touch trigger. Today
--    flipping `is_primary` doesn't bump anything → realtime
--    + watermarked pulls don't see the change. Adding the
--    trigger lets the existing sync engine handle it.
--
-- 6. `idx_form_submissions_parent_submission_id` perf index for
--    the "show all follow-ups for this concern" query that
--    currently seq-scans.
--
-- All migrations are idempotent (`if not exists`, NOT VALID,
-- DO blocks where needed).

-- =====================================================================
-- 1. program_members.display_name
-- =====================================================================

alter table public.program_members
  add column if not exists display_name text;

comment on column public.program_members.display_name is
  'Human-readable name for the members card. Populated by the '
  'app from auth.users.raw_user_meta_data on every membership '
  'upsert. NULL falls back to the UUID prefix in the UI.';

-- =====================================================================
-- 2. Normalize legacy adult_role values, then add CHECK
-- =====================================================================

update public.adults
  set adult_role = 'specialist'
  where adult_role = 'adult';

-- Update the column default to match the Dart enum so new
-- cloud-side inserts (e.g. via SQL editor, future edge fn)
-- land in the canonical value.
alter table public.adults
  alter column adult_role set default 'specialist';

do $$
begin
  alter table public.adults
    add constraint adults_adult_role_check
    check (adult_role in ('lead', 'specialist', 'ambient'));
exception when duplicate_object then null;
end $$;

-- =====================================================================
-- 3. CHECK constraints on the other enum-like columns. NOT VALID
--    so existing rows with unexpected values don't block the
--    migration; new rows are validated. If you want to enforce
--    on existing rows later: `alter table … validate constraint`.
-- =====================================================================

do $$
begin
  alter table public.observation_attachments
    add constraint obs_attachments_kind_check
    check (kind in ('photo', 'video')) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.attendance
    add constraint attendance_status_check
    check (status in ('present', 'absent', 'late', 'leftEarly')) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.form_submissions
    add constraint form_submissions_status_check
    check (status in ('draft', 'active', 'completed', 'archived')) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.program_members
    add constraint program_members_role_check
    check (role in ('admin', 'teacher')) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.schedule_entries
    add constraint schedule_entries_kind_check
    check (kind in ('addition', 'override', 'cancellation')) not valid;
exception when duplicate_object then null;
end $$;

-- =====================================================================
-- 4. Promote adult_role_block_overrides.date to timestamptz
-- =====================================================================

do $$
declare
  current_type text;
begin
  select data_type into current_type
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'adult_role_block_overrides'
      and column_name = 'date';
  if current_type = 'date' then
    -- Cast existing rows: a `date` D becomes timestamptz
    -- '00:00 UTC' on day D, matching what the sync engine sees
    -- when it serializes Drift's DateTime back to ISO.
    alter table public.adult_role_block_overrides
      alter column date type timestamptz
      using (date::timestamptz);
  end if;
end $$;

-- =====================================================================
-- 5. parent_children: updated_at + touch trigger
-- =====================================================================

alter table public.parent_children
  add column if not exists updated_at timestamptz not null default now();

drop trigger if exists parent_children_touch on public.parent_children;
create trigger parent_children_touch
  before update on public.parent_children
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- 6. Missing perf index
-- =====================================================================

create index if not exists idx_form_submissions_parent_submission
  on public.form_submissions (parent_submission_id)
  where parent_submission_id is not null;
