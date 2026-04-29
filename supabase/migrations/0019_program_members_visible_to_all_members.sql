-- Let any member of a program see the full member list.
--
-- Earlier (0011): SELECT was admin-only — non-admins could see
-- only their own row. That meant a teacher who joined a program
-- via invite couldn't see who else was on the team. Useless.
-- The directory of members isn't sensitive among co-members; we
-- want it visible to anyone in the program.
--
-- New rule: SELECT is allowed when the requesting user is a
-- member of the same program (or it's their own row, which is
-- a subset but kept explicit so a brand-new join can read its
-- own membership before realtime/hydrate picks up the rest).
--
-- INSERT / UPDATE / DELETE stay admin-only — only admins can add
-- or remove members. Self-delete (leave program) is the existing
-- exception in the DELETE policy. Invite codes also stay admin-
-- only via the existing program_invites_select policy.
--
-- Idempotent (DROP + CREATE).

drop policy if exists program_members_select on public.program_members;
create policy program_members_select on public.program_members
  for select using (
    user_id = auth.uid()
    or public.is_program_member(program_members.program_id)
  );
