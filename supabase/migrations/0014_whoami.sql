-- Diagnostic function: lets the client ask the server "who am I?"
-- and compare against `currentUser.id` / JWT.sub.
--
-- Why we need this: the persistent 42501 ("new row violates RLS
-- for 'programs'") error happens when `auth.uid() = created_by`
-- evaluates to false. Either auth.uid() is null (no valid JWT
-- attached) or it's a different uuid than `created_by`. Without a
-- way to inspect what the server actually sees, we can't tell
-- which side of the equation is wrong.
--
-- This RPC returns `auth.uid()` rendered as text (so the client's
-- supabase-flutter library can call it without a uuid serializer
-- in the picture). Empty string → no JWT was attached or it was
-- rejected. A uuid → that's the user the SERVER thinks is
-- making the request. Compare with `currentUser.id` on the client.
--
-- Idempotent: `create or replace`.

create or replace function public.whoami()
returns text
language sql
stable
security invoker
as $$
  select coalesce(auth.uid()::text, '')
$$;

-- Make it callable by signed-in users. service_role / anon don't
-- need it but granting authenticated only is the principle of
-- least privilege.
grant execute on function public.whoami() to authenticated;

-- Also: a re-apply of the `programs_insert` policy. If migration
-- 0001 was applied on a different project (the user has been
-- chasing a 42501 even after rotating sessions, suggesting policy
-- drift), this resets it to the canonical "creator can insert"
-- form. No-op when 0001 already ran cleanly.
drop policy if exists programs_insert on public.programs;
create policy programs_insert on public.programs
  for insert with check (auth.uid() = created_by);
