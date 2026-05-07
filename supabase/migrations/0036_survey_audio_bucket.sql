-- Shared survey-audio cache. Every device populates and reads
-- from this bucket so Deepgram TTS is paid for once per phrase
-- across the entire program (not once per device, like the old
-- per-device filesystem / in-memory caches were).
--
-- Storage path layout: <voice>/<phraseHash>.mp3
--   * <voice>          — Aura-2 voice code, e.g. "asteria"
--   * <phraseHash>     — first 16 chars of the SHA-256 of the
--                        trimmed prompt text (matches the
--                        client-side `_phraseHash` in
--                        survey_audio_service.dart so any
--                        existing per-device caches keep their
--                        keys).
--
-- Policies:
--   * READ — public. The audio is just synthesised speech of
--     the canonical survey questions; nothing PII-sensitive.
--     Public read means clients don't need a session JWT to
--     fetch from the cache, which simplifies the kiosk pre-warm
--     path on devices that aren't signed in yet.
--   * WRITE — authenticated only. A signed-in user (any role)
--     can upload, so a kiosk that just paid for a Deepgram
--     fetch can populate the shared cache for everyone else.
--
-- Bucket name: survey-audio (kebab-case to match Supabase
-- storage conventions; the existing `media` bucket follows the
-- same pattern).

-- 1. Create the bucket. Public read.
insert into storage.buckets (id, name, public)
values ('survey-audio', 'survey-audio', true)
on conflict (id) do nothing;

-- 2. Read policy — public, no auth required.
create policy "survey-audio public read"
  on storage.objects for select
  using (bucket_id = 'survey-audio');

-- 3. Insert policy — authenticated users only.
create policy "survey-audio authenticated upload"
  on storage.objects for insert
  with check (
    bucket_id = 'survey-audio'
    and auth.role() = 'authenticated'
  );

-- 4. Update policy — authenticated users only (for upsert).
create policy "survey-audio authenticated update"
  on storage.objects for update
  using (
    bucket_id = 'survey-audio'
    and auth.role() = 'authenticated'
  );
