-- Follow-up linter cleanup pass after 0020:
--
--   * Move the `vector` extension out of `public`
--     ─ Supabase best practice: extensions live in `extensions`,
--       not `public`. Keeping them in `public` clutters the schema
--       and makes the linter twitchy. The Basecamp codebase doesn't
--       reference vector types, so the move is non-disruptive.
--
--   * Re-assert `media` storage bucket private
--     ─ 0008 created it with `public = false`. The linter flagged
--       it as allowing public listing, which means either the
--       dashboard flipped it back to public, or someone re-ran the
--       insert with a different value. Idempotent UPDATE forces it
--       back to private. The four RLS policies on storage.objects
--       already restrict per-program-member access; this just makes
--       sure the bucket-level toggle agrees.
--
--   * Same defensive pass on `db_backups` so both private buckets
--     stay private regardless of dashboard drift.
--
-- Items NOT addressed here (they're outside SQL):
--
--   * `is_program_admin` / `is_program_member` flagged SECURITY
--     DEFINER + executable. Intentional — they exist precisely to
--     break RLS recursion on program_members. EXECUTE was already
--     revoked from PUBLIC and granted only to `authenticated` in
--     0020. Calling them as user X with program_id Y leaks no info
--     beyond what X already knows about X's own membership. The
--     lint is informational, not a real vulnerability.
--
--   * Leaked-password-protection setting. Project-level Auth
--     toggle in the Supabase dashboard (Authentication → Settings).
--     Not migratable.
--
--   * Unused-index infos. Need the linter's specific list before
--     dropping anything blind — the per-(program_id, updated_at)
--     indexes on every entity table look unused without context
--     but they're load-bearing for the sync engine's watermarked
--     pulls.

-- =====================================================================
-- vector extension → extensions schema
-- =====================================================================
--
-- Standard Supabase setup ships an `extensions` schema with most
-- extensions already there. If `vector` is in `public`, move it.
-- The DO block guards against:
--   * the extension not being installed (skip silently)
--   * the extensions schema not existing (create it first)
--   * the extension already being in extensions (no-op)

do $$
declare
  cur_schema text;
begin
  select n.nspname
    into cur_schema
    from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'vector';

  if cur_schema is null then
    -- Extension isn't installed. Nothing to move.
    return;
  end if;

  if cur_schema = 'extensions' then
    -- Already in the right place.
    return;
  end if;

  -- Make sure the target schema exists.
  create schema if not exists extensions;

  -- Move the extension. ALTER EXTENSION SET SCHEMA carries every
  -- type, function, and operator the extension owns into the new
  -- schema in one shot. References that didn't qualify the schema
  -- (e.g. `vector(1536)`) will resolve via search_path — Supabase's
  -- default already includes `extensions`.
  execute 'alter extension vector set schema extensions';
end $$;

-- =====================================================================
-- Storage buckets — re-assert private
-- =====================================================================
--
-- Both buckets were defined private in 0003 / 0008. Re-asserting
-- here is cheap (UPDATE is idempotent) and protects against drift
-- from the dashboard's bucket-settings toggle. The bucket's `public`
-- flag governs whether the per-object download URL works without
-- a signed token — independent of the SELECT policies on
-- storage.objects, which still enforce program-member scoping.

update storage.buckets
   set public = false
 where id in ('db_backups', 'media')
   and public is distinct from false;
