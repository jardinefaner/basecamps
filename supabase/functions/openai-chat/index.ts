// OpenAI chat-completions proxy.
//
// Why this exists: shipping the OpenAI API key in a public web bundle
// would let anyone scrape it and run up our bill. Putting the key in a
// secret edge-function environment lets clients call OpenAI through us
// without ever seeing the key. The edge function passes its caller's
// Supabase JWT through Supabase's built-in auth (Deno function runner
// validates the `Authorization: Bearer <jwt>` header against
// auth.users), so only signed-in users can hit it.
//
// Body contract: this is a thin pass-through. The client sends a
// JSON payload that matches the OpenAI chat-completions request exactly
// (model, messages, temperature, response_format, etc) and we forward
// it as-is. No allowlisting of models, no rate limiting per user yet —
// add those when usage demands it. Today the goal is "make the feature
// work on the public web bundle" without bigger redesign.
//
// Deploy:  supabase functions deploy openai-chat
// Secret:  supabase secrets set OPENAI_API_KEY=sk-...
//
// Local test:
//   curl -X POST \
//     "https://<project>.supabase.co/functions/v1/openai-chat" \
//     -H "Authorization: Bearer <user-jwt>" \
//     -H "Content-Type: application/json" \
//     -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}'

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

// Standard CORS headers — the bundle on github.io and on dev origins
// (localhost:*) calls this function from the browser, so we have to
// answer preflight OPTIONS requests with permissive CORS.
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

  // The Supabase Functions runtime validates the Authorization header
  // against auth.users by default (verify_jwt = true, the default in
  // config.toml), so by the time we get here the caller is signed in.
  // Belt-and-suspenders: re-check that we got an Authorization header.
  const auth = req.headers.get("Authorization");
  if (!auth || !auth.startsWith("Bearer ")) {
    return json({ error: "missing or malformed Authorization header" }, 401);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    // Operator hasn't run `supabase secrets set OPENAI_API_KEY=...`
    // yet. Surface this as a 500 with a hint so the deploy story
    // doesn't silently break.
    return json(
      { error: "OPENAI_API_KEY secret not configured on this project" },
      500,
    );
  }

  let payload: unknown;
  try {
    payload = await req.json();
  } catch (_e) {
    return json({ error: "invalid JSON body" }, 400);
  }

  // Forward to OpenAI. We don't manipulate the response — same status,
  // same body, just routed through us with our key.
  const upstream = await fetch(
    "https://api.openai.com/v1/chat/completions",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify(payload),
    },
  );

  // Stream the response body straight through so chat-completions
  // payloads (a few KB typical) don't get buffered. Preserve the
  // status so OpenAI errors (429 rate-limit, 400 schema-mismatch) are
  // visible to the client.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      ...corsHeaders,
      "Content-Type":
        upstream.headers.get("Content-Type") ?? "application/json",
    },
  });
});

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
