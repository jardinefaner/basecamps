-- Identity binding (3/4): program_invites.adult_id
--
-- An invite can now optionally name a specific Adult row. When the
-- recipient redeems via the accept-invite edge function, the
-- function stamps `adults.auth_user_id = <recipient's user id>` on
-- the named row — that's the moment "Maya" the pre-created adult
-- becomes "Maya the signed-in user."
--
-- Why optional rather than required:
--
-- * Existing invite flow (admin creates invite → recipient joins
--   the program as a generic member) still works. Old invites
--   with NULL adult_id continue to do nothing adult-side; they
--   just create a program_members row like before.
--
-- * Programs that don't yet author per-adult rows (small daycare,
--   solo provider) can keep using anonymous invites until they
--   start using the identity-aware features (monthly plan gating,
--   etc.). Forcing every invite to bind would break those flows.
--
-- FK to public.adults(id) on delete set null — if the admin
-- deletes the pre-created adult row before the recipient redeems,
-- the invite drops back to generic-membership mode rather than
-- breaking the redemption.

-- adults.id is `text` in this schema (Drift-generated string ids,
-- not Postgres uuids), so the FK column matches that type.
alter table public.program_invites
  add column if not exists adult_id text
  references public.adults(id) on delete set null;
