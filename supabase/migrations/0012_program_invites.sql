-- Slice 3: program invitations.
--
-- A short, human-readable code that an admin generates and shares
-- (text, email, slack…) so a teacher can join an existing program
-- without the admin having to know their auth user id ahead of time.
--
-- Lifecycle:
--   1. Admin generates a code → row inserted with `accepted_*` null
--      and `expires_at = now() + interval '7 days'` (default).
--   2. Recipient (signed in to Supabase) calls the edge function
--      `accept_invite(code)`. The function (with service-role
--      privileges) validates the code, inserts a `program_members`
--      row for `auth.uid()`, and stamps `accepted_by + accepted_at`.
--      Returns the program id + name so the client can switch to it.
--   3. Subsequent calls with the same code fail (single-use).
--
-- Why an edge function instead of direct INSERT-with-RLS:
--   * Recipients aren't members yet, so RLS on `program_members`
--     wouldn't normally let them insert. The bootstrap-creator
--     special case (used in 0011) doesn't apply here — the
--     recipient isn't the program creator.
--   * The function bypasses RLS via service-role and applies its
--     own validation (code valid, not expired, not yet accepted),
--     which is the exact semantic we want.
--
-- Why codes can't be SELECTed by recipients:
--   * Random-guess attacks. If anyone could `select * from
--     program_invites where code = ?` they could brute-force codes
--     across the entire program-invites table. The edge function
--     hides codes behind explicit single-row redemption + RPC rate
--     limiting (Supabase project-level), and admins can list /
--     revoke their own codes via the `created_by = auth.uid()`
--     SELECT policy.

create table if not exists public.program_invites (
  -- 8 chars, uppercase letters + digits, no I/O/0/1 (visual confusion).
  -- Generated client-side; PK collision is vanishingly rare at this
  -- alphabet size but the unique-key error path falls back to a
  -- regenerate-and-retry on the client.
  code text primary key,
  program_id text not null
    references public.programs(id) on delete cascade,
  -- Role assigned to the recipient on accept. Defaults to 'teacher'
  -- so admin-creation is opt-in.
  role text not null default 'teacher',
  -- Admin who generated the invite.
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

-- Per-program listing (admin tooling: "show me all my outstanding
-- invites for this program") — index on (program_id, created_at).
create index if not exists idx_program_invites_program_created
  on public.program_invites (program_id, created_at desc);

-- =====================================================================
-- RLS
-- =====================================================================

alter table public.program_invites enable row level security;

-- SELECT: admins of the program (via `is_program_admin` from 0011)
-- can read their program's invites for the management UI. Recipients
-- redeem via the edge function and never need to read codes
-- directly. Codes are intentionally not in the SELECT scope of
-- non-admins to prevent enumeration.
drop policy if exists program_invites_select on public.program_invites;
create policy program_invites_select on public.program_invites
  for select using (
    public.is_program_admin(program_invites.program_id)
  );

-- INSERT: admins of the target program. The `created_by =
-- auth.uid()` clause prevents an admin of program A from creating
-- an invite that pretends to be from someone else.
drop policy if exists program_invites_insert on public.program_invites;
create policy program_invites_insert on public.program_invites
  for insert with check (
    created_by = auth.uid()
    and public.is_program_admin(program_invites.program_id)
  );

-- UPDATE / DELETE: admins. Used by the (future) "revoke this
-- invite" action. Edge function uses service-role, bypassing RLS
-- to mark `accepted_*` regardless of who's calling.
drop policy if exists program_invites_update on public.program_invites;
create policy program_invites_update on public.program_invites
  for update using (
    public.is_program_admin(program_invites.program_id)
  );

drop policy if exists program_invites_delete on public.program_invites;
create policy program_invites_delete on public.program_invites
  for delete using (
    public.is_program_admin(program_invites.program_id)
  );
