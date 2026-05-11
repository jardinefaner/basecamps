-- v65 / cloud migration 0039: thank-you-card "prints" sync.
--
-- Until now `prints` rows lived only on the originating device
-- — the snapshot was a PNG written to the app's docs folder
-- and the row pointed at a relative path that meant nothing on
-- any other device. Now the client always embeds the PNG as a
-- `data:image/png;base64,...` URL in `snapshot_path`, so the
-- column IS the bytes; the row alone is enough to render the
-- card on any device the user signs in to.
--
-- Storage choice: NO separate Storage bucket. Thank-you cards
-- are ~50-100KB each; Postgres TEXT toasts them transparently;
-- per-program lifetime volume is a few hundred. Inline column
-- avoids the extra round-trip + IAM policy a bucket would
-- require, and the bytes travel through the same sync engine
-- every other row uses.

create table if not exists public.prints (
  id text primary key,
  survey_id text,
  session_id text,
  child_name text not null default '',
  kind text not null,
  snapshot_path text not null,
  metadata_json text,
  program_id text references public.programs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_prints_program_updated
  on public.prints (program_id, updated_at);
create index if not exists idx_prints_survey
  on public.prints (survey_id);

drop trigger if exists prints_touch on public.prints;
create trigger prints_touch
  before update on public.prints
  for each row execute function public.touch_updated_at();

-- RLS — program members can SELECT/INSERT/UPDATE in their program.
alter table public.prints enable row level security;

drop policy if exists prints_select on public.prints;
create policy prints_select on public.prints
  for select using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = prints.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists prints_insert on public.prints;
create policy prints_insert on public.prints
  for insert with check (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = prints.program_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists prints_update on public.prints;
create policy prints_update on public.prints
  for update using (
    program_id is not null
    and exists (
      select 1 from public.program_members m
      where m.program_id = prints.program_id
        and m.user_id = auth.uid()
    )
  );

-- Realtime — opt into the broadcast publication so a teacher on
-- Device B sees a card the moment Device A finishes a session.
alter table public.prints replica identity full;
alter publication supabase_realtime add table public.prints;
