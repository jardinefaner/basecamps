// Deepgram temp-token grant.
//
// Why this exists: Deepgram's realtime listen endpoint is a
// WebSocket, and Supabase Edge Functions can't proxy WebSockets
// directly. The client has to talk to Deepgram itself. But shipping
// the long-lived project key in a client bundle is a leak — anyone
// who scrapes the app can connect to Deepgram on our dime forever.
//
// Deepgram's `/v1/auth/grant` endpoint exchanges the long-lived
// project key for a short-lived (default 30s) JWT scoped to the
// project. Pattern:
//   1. Client calls THIS edge function with their Supabase JWT.
//   2. We verify the caller is signed in (Supabase does this for
//      us via verify_jwt) and forward to Deepgram's grant endpoint
//      with the secret project key.
//   3. We return the 30s JWT to the client.
//   4. Client opens its WebSocket to Deepgram with that JWT.
//   5. JWT expires in 30s — long enough for one capture session
//      to start streaming. Re-fetch for the next session.
//
// Result: a leaked client bundle exposes at most a 30-second
// window, and only to whoever was already authenticated.
//
// Deploy:  supabase functions deploy deepgram-token
// Secret:  supabase secrets set DEEPGRAM_API_KEY=<project-key>
//
// Local test:
//   curl -X POST \
//     "https://<project>.supabase.co/functions/v1/deepgram-token" \
//     -H "Authorization: Bearer <user-jwt>"

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

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
    return json({ error: "method not allowed" }, 405);
  }

  // Belt-and-suspenders: the function runtime already enforces
  // verify_jwt by default, but cross-check the header so a future
  // config change doesn't silently open this up to anonymous calls.
  const auth = req.headers.get("Authorization");
  if (!auth || !auth.startsWith("Bearer ")) {
    return json({ error: "missing or malformed Authorization header" }, 401);
  }

  const apiKey = Deno.env.get("DEEPGRAM_API_KEY");
  if (!apiKey) {
    return json(
      { error: "DEEPGRAM_API_KEY secret not configured on this project" },
      500,
    );
  }

  // Deepgram's grant endpoint takes the project key in
  // `Authorization: Token <key>` and returns
  // `{ access_token: string, expires_in: number }`. Default TTL is
  // 30 seconds; pass `ttl_seconds` in the body to extend.
  // https://developers.deepgram.com/docs/auth-grant
  const upstream = await fetch(
    "https://api.deepgram.com/v1/auth/grant",
    {
      method: "POST",
      headers: {
        "Authorization": `Token ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    },
  );

  if (!upstream.ok) {
    const text = await upstream.text();
    return json(
      { error: "deepgram grant failed", status: upstream.status, body: text },
      502,
    );
  }

  const payload = await upstream.json();
  return json(payload, 200);
});

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
