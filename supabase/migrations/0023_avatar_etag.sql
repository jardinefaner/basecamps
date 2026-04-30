-- Per-upload content tag for avatars (v51).
--
-- The bucket key (`avatar_storage_path`) is stable per row id, so
-- a teacher re-picking a photo overwrites bytes at the same key.
-- Without a signal, every other device's local cache keeps
-- serving the old bytes forever — there's nothing in a row update
-- that says "the bytes at this key changed."
--
-- Fix: each upload stamps a fresh random etag here, alongside the
-- storage path. The client's avatar resolver uses
-- `(storage_path, etag)` as its cache key — any change pulls the
-- new bytes once, then everyone reads from the local cache again.
--
-- Sync semantics:
--   * Pushed alongside `avatar_storage_path` via the partial-
--     update path (field-level dirty tracking ensures only the
--     columns that actually changed travel).
--   * Pulled like any other column. Realtime subscriptions
--     deliver etag changes within a second of the upstream
--     write, which is what makes cross-device invalidation
--     feel instant.
--   * Replication is already on for both tables (0007 +
--     0017's REPLICA IDENTITY FULL covers it).
--
-- Backwards compat:
--   * NULL etag is a wildcard — clients treat null-vs-null as a
--     match, so legacy rows uploaded before v51 keep rendering
--     the cached bytes they already have. The first re-upload
--     pops in a non-null etag and invalidation kicks in for that
--     row everywhere.
--
-- Idempotent (IF NOT EXISTS).

alter table public.adults
  add column if not exists avatar_etag text;

alter table public.children
  add column if not exists avatar_etag text;
