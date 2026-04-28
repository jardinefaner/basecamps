// accept-invite — redeem a program-invite code.
//
// Why an edge function (not direct INSERT-with-RLS): the recipient
// isn't a member of the target program yet, so the
// `program_members` INSERT policy wouldn't normally accept their
// row. The bootstrap-creator special case in 0011 only applies to
// the program's `created_by`. So we need a privileged path that
// (a) validates the invite and (b) inserts on the user's behalf
// using the service-role client.
//
// Body contract:
//   POST { code: string }
//   200  { program_id, program_name, role }
//   400  { error: 'missing_code' | 'invalid_code' | 'expired' |
//                  'already_used' | 'already_member' }
//   401  { error: 'unauthenticated' }
//   500  { error: 'server', detail }
//
// Deploy:  supabase functions deploy accept-invite
// Secrets needed (already set for the project):
//   SUPABASE_URL                — provided by the runtime
//   SUPABASE_SERVICE_ROLE_KEY   — provided by the runtime
//
// The function relies on Supabase's default `verify_jwt = true`
// (config.toml) so by the time the body runs we know the caller
// is signed in and `auth.uid()` resolves to their user id.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // Pull the caller's JWT so we can derive their user id. The
  // function runtime has already validated it (verify_jwt: true);
  // we just decode the `sub` claim. Easier than re-running the
  // whole verification.
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const userId = userIdFromJwt(token);
  if (!userId) {
    return json({ error: "unauthenticated" }, 401);
  }

  let body: { code?: unknown };
  try {
    body = await req.json();
  } catch (_err) {
    return json({ error: "invalid_body" }, 400);
  }
  const code = typeof body.code === "string"
    ? body.code.trim().toUpperCase()
    : "";
  if (code.length === 0) {
    return json({ error: "missing_code" }, 400);
  }

  // Service-role client bypasses RLS so we can read the invite
  // row regardless of caller, and insert into program_members
  // for a recipient who isn't a member yet.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );

  // 1. Look up the invite. Single() so a missing row throws.
  const { data: invite, error: inviteErr } = await supabase
    .from("program_invites")
    .select("code, program_id, role, expires_at, accepted_by")
    .eq("code", code)
    .maybeSingle();
  if (inviteErr) {
    return json({ error: "server", detail: inviteErr.message }, 500);
  }
  if (!invite) {
    return json({ error: "invalid_code" }, 400);
  }
  if (invite.accepted_by) {
    return json({ error: "already_used" }, 400);
  }
  if (new Date(invite.expires_at).getTime() < Date.now()) {
    return json({ error: "expired" }, 400);
  }

  // 2. Idempotency: if the user is already a member of this
  //    program (e.g. they redeemed before, or were added directly),
  //    return success with the program details so the client can
  //    switch to it without surfacing "already_used" confusingly.
  const { data: existingMember } = await supabase
    .from("program_members")
    .select("program_id, role")
    .eq("program_id", invite.program_id)
    .eq("user_id", userId)
    .maybeSingle();

  if (!existingMember) {
    const { error: memberErr } = await supabase
      .from("program_members")
      .insert({
        program_id: invite.program_id,
        user_id: userId,
        role: invite.role,
      });
    if (memberErr) {
      return json({ error: "server", detail: memberErr.message }, 500);
    }
  }

  // 3. Mark the invite consumed. Single-use semantics: stamp
  //    `accepted_by + accepted_at` so a second redemption fails
  //    with `already_used`. Best-effort — if this fails the
  //    membership still landed, which is the important part.
  await supabase
    .from("program_invites")
    .update({
      accepted_by: userId,
      accepted_at: new Date().toISOString(),
    })
    .eq("code", code);

  // 4. Hydrate the program name for the success toast — also
  //    serves as a sanity check that the program still exists.
  //    The membership FK we just inserted would have failed if
  //    the program was deleted, but if the FK was deferred or
  //    if we're hitting a partial state, we still want to
  //    surface program_not_found rather than a generic server
  //    error.
  const { data: program } = await supabase
    .from("programs")
    .select("name")
    .eq("id", invite.program_id)
    .maybeSingle();
  if (!program) {
    return json({ error: "program_not_found" }, 400);
  }

  return json({
    program_id: invite.program_id,
    program_name: program.name as string,
    role: existingMember?.role ?? invite.role,
  }, 200);
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
    },
  });
}

/// Decode the `sub` claim from a JWT without verifying — Supabase's
/// runtime already verified the signature; we just need the user
/// id. Returns null on malformed tokens.
function userIdFromJwt(token: string): string | null {
  if (!token) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(atob(padBase64(parts[1])));
    const sub = payload?.sub;
    return typeof sub === "string" ? sub : null;
  } catch (_err) {
    return null;
  }
}

function padBase64(raw: string): string {
  const padded = raw.replace(/-/g, "+").replace(/_/g, "/");
  const mod = padded.length % 4;
  return mod === 0 ? padded : padded + "=".repeat(4 - mod);
}
