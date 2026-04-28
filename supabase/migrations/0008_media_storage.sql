-- Slice C optimization #5: Storage-backed media sync.
--
-- Adds a `media` Storage bucket so observation attachments + child
-- and adult avatars follow rows across devices instead of staying
-- pinned to whichever device captured them.
--
-- Schema additions: each row that points at a local file gains a
-- `storage_path` text column. The local_path / avatar_path field
-- stays for cache-or-original-on-this-device behavior; storage_path
-- is the bucket key used to (re)download on other devices.
--
-- Bucket layout: `<programId>/<rowId>.<ext>`. Membership-scoped
-- like db_backups — RLS gates by program_members.
--
-- Migration is purely additive — existing rows have null
-- storage_path until the device that owns the file uploads it.
-- A background backfill (client-side) walks observation_attachments
-- and ensures each local file has a cloud counterpart.

-- =====================================================================
-- Schema additions
-- =====================================================================

alter table public.observation_attachments
  add column if not exists storage_path text;

alter table public.children
  add column if not exists avatar_storage_path text;

alter table public.adults
  add column if not exists avatar_storage_path text;

-- =====================================================================
-- Storage bucket
-- =====================================================================

insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do nothing;

-- =====================================================================
-- RLS — same shape as db_backups (0003).
-- First path segment is the program_id, joined to program_members
-- for membership-scoped access. Different bucket so policies don't
-- collide with db_backups.
-- =====================================================================

drop policy if exists "media_select" on storage.objects;
create policy "media_select" on storage.objects
  for select
  using (
    bucket_id = 'media'
    and exists (
      select 1 from public.program_members m
      where m.user_id = auth.uid()
        and m.program_id = (storage.foldername(name))[1]
    )
  );

drop policy if exists "media_insert" on storage.objects;
create policy "media_insert" on storage.objects
  for insert
  with check (
    bucket_id = 'media'
    and exists (
      select 1 from public.program_members m
      where m.user_id = auth.uid()
        and m.program_id = (storage.foldername(name))[1]
    )
  );

drop policy if exists "media_update" on storage.objects;
create policy "media_update" on storage.objects
  for update
  using (
    bucket_id = 'media'
    and exists (
      select 1 from public.program_members m
      where m.user_id = auth.uid()
        and m.program_id = (storage.foldername(name))[1]
    )
  );

drop policy if exists "media_delete" on storage.objects;
create policy "media_delete" on storage.objects
  for delete
  using (
    bucket_id = 'media'
    and exists (
      select 1 from public.program_members m
      where m.user_id = auth.uid()
        and m.program_id = (storage.foldername(name))[1]
    )
  );
