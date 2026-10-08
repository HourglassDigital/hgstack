import { createClient } from "npm:@supabase/supabase-js@2"

// Capture endpoint for Consume. The "Consume" Apple Shortcut POSTs
// {"url": "..."} here with `Authorization: Bearer <CONSUME_CAPTURE_TOKEN>`,
// and the link lands in consume_items for the weekly /consume triage.
//
// Deploy with --no-verify-jwt: the token is our own secret, not a Supabase
// JWT, so the platform's default JWT check would reject every request with a
// 401 before this code runs. The Bearer check below is the auth.
//
// Capture stays dumb on purpose: no title fetching or enrichment here, so the
// share-sheet tap returns in about a second. Labelling happens at review time.

const VALID_SOURCES = ["shortcut", "manual"]

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" })

  const expected = Deno.env.get("CONSUME_CAPTURE_TOKEN")
  if (!expected || req.headers.get("Authorization") !== `Bearer ${expected}`) {
    return json(401, { error: "Unauthorized" })
  }

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json(400, { error: "Invalid JSON" })
  }

  const url = typeof body.url === "string" ? body.url.trim() : ""
  const source = typeof body.source === "string" ? body.source : "shortcut"

  try {
    const parsed = new URL(url)
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") throw new Error()
  } catch {
    return json(400, { error: "url must be a valid http(s) URL" })
  }
  if (!VALID_SOURCES.includes(source)) {
    return json(400, { error: `source must be one of: ${VALID_SOURCES.join(", ")}` })
  }

  // SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected into every Edge
  // Function by the platform. The service role bypasses RLS.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data, error } = await supabase
    .from("consume_items")
    .insert({ url, source })
    .select("id")
    .single()

  if (error) return json(500, { error: error.message })
  return json(201, { success: true, id: data.id })
})
