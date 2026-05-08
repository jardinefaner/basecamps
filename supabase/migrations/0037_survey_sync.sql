-- Cloud sync for the surveys feature.
--
-- Until now the entire surveys feature was local-only — the
-- Drift schema had no cloud parity. A teammate creating a survey
-- on Device A meant Device B saw an empty list. This migration
-- closes that gap by mirroring the three Drift tables into
-- Postgres so the sync engine can push/pull rows like it does
-- for observations / children / monthly plan.
--
-- Three tables, one parent + two cascades:
--   surveys             — config: site/classroom/age band/voice/
--                         pin/style/questions JSON/schools list.
--                         The parent. program_id scoped.
--   survey_sessions     — one row per kid going through the
--                         kiosk. References its survey via
--                         survey_id. Carries the per-session
--                         school answer from the pre-flight gate.
--   survey_responses    — one row per question answer. References
--                         survey_id + session_id. Carries
--                         mood_value / selections_json /
--                         transcription depending on type.
--
-- All three are program_id-scoped via RLS. Sessions and responses
-- piggyback on their parent survey's program_id (denormalised for
-- index simplicity — every row carries program_id directly so the
-- pull-on-launch query stays a single index scan).
--
-- Soft-delete on `surveys` only. Sessions and responses cascade
-- on hard delete via FK; teachers don't soft-delete those
-- individually.

-- =====================================================================
-- surveys (parent)
-- =====================================================================

create table if not exists public.surveys (
  id text primary key,
  site_name text not null,
  classroom text not null,
  age_band text not null,
  pin_hash text not null,
  audio_mode text not null,
  voice_id text not null,
  style text not null default 'marble_jar',
  questions_json text not null,
  schools_json text not null default '[]',
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_surveys_program_updated
  on public.surveys (program_id, updated_at);

drop trigger if exists surveys_touch on public.surveys;
create trigger surveys_touch
  before update on public.surveys
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- survey_sessions (cascade child of surveys)
-- =====================================================================

create table if not exists public.survey_sessions (
  id text primary key,
  survey_id text not null
    references public.surveys(id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  child_count bigint not null default 0,
  -- Pre-flight gate answer ('KIPP' or whatever the kid typed /
  -- picked from the configured roster). Nullable for sessions
  -- created before the gate landed (v61 client schema).
  school text,
  -- Denormalised so RLS doesn't have to JOIN through surveys
  -- on every row. Maintained by the client; the engine writes
  -- it on insert / update.
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_survey_sessions_survey
  on public.survey_sessions (survey_id);
create index if not exists idx_survey_sessions_program_updated
  on public.survey_sessions (program_id, updated_at);

drop trigger if exists survey_sessions_touch on public.survey_sessions;
create trigger survey_sessions_touch
  before update on public.survey_sessions
  for each row execute function public.touch_updated_at();

-- =====================================================================
-- survey_responses (cascade child of survey_sessions)
-- =====================================================================

create table if not exists public.survey_responses (
  id text primary key,
  survey_id text not null
    references public.surveys(id) on delete cascade,
  session_id text not null
    references public.survey_sessions(id) on delete cascade,
  question_id text not null,
  -- 'mood' | 'multi_select' | 'audio'
  answer_type text not null,
  -- Likert index (set when answer_type = 'mood'; null otherwise)
  mood_value bigint,
  -- JSON array of selected option ids (set when answer_type =
  -- 'multi_select'; null otherwise)
  selections_json text,
  -- Local file path on the originating device. Useless on other
  -- devices until Storage-backed audio sync ships; kept on the
  -- row so cascade counts match and we can light up file sync
  -- later without a backfill (same approach observations took
  -- with attachments).
  audio_file_path text,
  transcription text,
  reaction_time_ms bigint,
  duration_ms bigint,
  is_practice boolean not null default false,
  -- Denormalised program_id (see survey_sessions for rationale).
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists idx_survey_responses_session
  on public.survey_responses (session_id);
create index if not exists idx_survey_responses_program_created
  on public.survey_responses (program_id, created_at);

-- =====================================================================
-- RLS — same pattern as observations / monthly plan: program
-- members can SELECT/INSERT/UPDATE rows in their program.
-- DELETE goes through the soft-delete path on surveys; for
-- sessions and responses, FK cascade handles cleanup when a
-- survey is deleted.
-- =====================================================================

alter table public.surveys enable row level security;
alter table public.survey_sessions enable row level security;
alter table public.survey_responses enable row level security;

-- ——— surveys ————————————————————————————————————————————————————

drop policy if exists surveys_select on public.surveys;
create policy surveys_select on public.surveys
  for select using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = surveys.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists surveys_insert on public.surveys;
create policy surveys_insert on public.surveys
  for insert with check (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = surveys.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists surveys_update on public.surveys;
create policy surveys_update on public.surveys
  for update using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = surveys.program_id
        and m.user_id = auth.uid()
    )
  );

-- ——— survey_sessions ——————————————————————————————————————————————

drop policy if exists survey_sessions_select on public.survey_sessions;
create policy survey_sessions_select on public.survey_sessions
  for select using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = survey_sessions.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists survey_sessions_insert on public.survey_sessions;
create policy survey_sessions_insert on public.survey_sessions
  for insert with check (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = survey_sessions.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists survey_sessions_update on public.survey_sessions;
create policy survey_sessions_update on public.survey_sessions
  for update using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = survey_sessions.program_id
        and m.user_id = auth.uid()
    )
  );

-- ——— survey_responses ——————————————————————————————————————————————

drop policy if exists survey_responses_select on public.survey_responses;
create policy survey_responses_select on public.survey_responses
  for select using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = survey_responses.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists survey_responses_insert on public.survey_responses;
create policy survey_responses_insert on public.survey_responses
  for insert with check (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = survey_responses.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists survey_responses_update on public.survey_responses;
create policy survey_responses_update on public.survey_responses
  for update using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = survey_responses.program_id
        and m.user_id = auth.uid()
    )
  );

-- =====================================================================
-- Realtime — opt the new tables into the supabase_realtime publication
-- so a fresh teammate sees rows appear as they're created on other
-- devices. Replica identity FULL so updates carry the full row
-- (matches the pattern from migration 0017).
-- =====================================================================

alter table public.surveys replica identity full;
alter table public.survey_sessions replica identity full;
alter table public.survey_responses replica identity full;

alter publication supabase_realtime add table public.surveys;
alter publication supabase_realtime add table public.survey_sessions;
alter publication supabase_realtime add table public.survey_responses;
