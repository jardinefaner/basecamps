-- v54: adults.auth_user_id
--
-- Identity binding. Each Adult row optionally carries the
-- Supabase auth user id of the signed-in account that *is* this
-- adult. The accept-invite edge function will stamp this column
-- when an invite carrying `adult_id` is redeemed — that's the
-- ceremony for "Maya signs up, the row admin pre-created for her
-- now belongs to her account."
--
-- Why nullable + no unique constraint:
--
-- * Nullable — admin-pre-created rows live unbound until invite
--   redemption. Ex-staff and historical-only rows (referenced by
--   observations from years ago) stay unbound forever; nothing
--   forces them to point at a live auth user.
--
-- * No `unique`-on-auth_user_id — a single auth user could be
--   bound to one Adult per program, but the cross-program
--   uniqueness is a soft business rule, not a schema invariant.
--   We let the application code enforce "one bind per program"
--   in the invite-accept flow rather than fighting an ALTER that
--   trips on legitimate edge cases (admin manually re-assigns,
--   user changes accounts, etc.).
--
-- The FK to auth.users(id) on delete set null means "if the auth
-- account gets deleted, the adult row stays but cleanly
-- unbinds" — keeps observation-attribution history intact even
-- after a user purge.

alter table public.adults
  add column if not exists auth_user_id uuid
  references auth.users(id) on delete set null;

-- Lookup index — `currentAdultProvider` queries by auth_user_id
-- on every session change to find "which Adult row am I." Partial
-- to keep it cheap (most rows are bound; for the unbound rows the
-- index simply doesn't include them).
create index if not exists idx_adults_auth_user_id
  on public.adults (auth_user_id)
  where auth_user_id is not null;
