-- Slice B: per-program JSON snapshot bucket.
--
-- Creates a private Storage bucket where each program writes a
-- single `<programId>/snapshot.json` blob. Read/write is gated by
-- RLS on the bucket's path so only members of a program can touch
-- that program's folder. The path layout is intentional: the
-- first path segment IS the program_id, which RLS extracts via
-- `storage.foldername(name)[1]` and joins to `program_members`.
--
-- Apply in Supabase Dashboard → SQL Editor (paste & run). Bucket
-- creation is idempotent; the policy DROP/CREATE pattern lets you
-- re-run this file safely after edits.
--
-- Why a Storage bucket instead of a column on a table:
--  - Snapshots are 100kb–multi-MB blobs. Postgres can store them
--    but bucketing keeps the row size of every other table sane
--    and lets clients stream the download directly.
--  - One snapshot per program means the bucket has at most ~one
--    object per program — small. Cleanup on program delete is
--    handled by the trigger below.

-- =====================================================================
-- Bucket
-- =====================================================================

insert into storage.buckets (id, name, public)
values ('db_backups', 'db_backups', false)
on conflict (id) do nothing;

-- =====================================================================
-- RLS — bucket-level policies on storage.objects
-- =====================================================================
--
-- One policy per CRUD verb. The `bucket_id = 'db_backups'` clause
-- scopes each policy to our bucket so other buckets remain
-- governed by their own rules. The membership check pulls the
-- first folder segment (`storage.foldername(name)` returns the
-- path components as an array) and looks for a matching
-- program_members row.

drop policy if exists "db_backups_select" on storage.objects;
create policy "db_backups_select" on storage.objects
  for select
  using (
    bucket_id = 'db_backups'
    and exists (
      select 1 from public.program_members m
      where m.user_id = auth.uid()
        and m.program_id = (storage.foldername(name))[1]
    )
  );

drop policy if exists "db_backups_insert" on storage.objects;
create policy "db_backups_insert" on storage.objects
  for insert
  with check (
    bucket_id = 'db_backups'
    and exists (
      select 1 from public.program_members m
      where m.user_id = auth.uid()
        and m.program_id = (storage.foldername(name))[1]
    )
  );

drop policy if exists "db_backups_update" on storage.objects;
create policy "db_backups_update" on storage.objects
  for update
  using (
    bucket_id = 'db_backups'
    and exists (
      select 1 from public.program_members m
      where m.user_id = auth.uid()
        and m.program_id = (storage.foldername(name))[1]
    )
  );

drop policy if exists "db_backups_delete" on storage.objects;
create policy "db_backups_delete" on storage.objects
  for delete
  using (
    bucket_id = 'db_backups'
    and exists (
      select 1 from public.program_members m
      where m.user_id = auth.uid()
        and m.program_id = (storage.foldername(name))[1]
    )
  );

-- =====================================================================
-- Cleanup on program delete
-- =====================================================================
--
-- When a program row is deleted, also remove its snapshot blob.
-- Storage objects don't auto-cascade from arbitrary tables; this
-- trigger handles it explicitly. Best-effort — failure (e.g.
-- because the object never existed) doesn't block the program
-- deletion.

create or replace function public.cleanup_program_backup()
returns trigger language plpgsql security definer as $$
begin
  delete from storage.objects
   where bucket_id = 'db_backups'
     and (storage.foldername(name))[1] = old.id;
  return old;
end $$;

drop trigger if exists programs_cleanup_backup on public.programs;
create trigger programs_cleanup_backup
  after delete on public.programs
  for each row execute function public.cleanup_program_backup();
