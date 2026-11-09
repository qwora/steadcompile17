// Spends one unit of the caller's AI budget (60/hour) via the claim_ai_call RPC, using THEIR token.
// That also proves a real signed-in user: the public anon key (role "anon") can't execute the RPC,
// even though the gateway's verify_jwt lets it through.
export async function claimAiCall(req: Request, fetchFn: typeof fetch = fetch): Promise<"ok" | "unauthorized" | "rate_limited"> {
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return "unauthorized";
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) return "unauthorized";
  try {
    const res = await fetchFn(`${url}/rest/v1/rpc/claim_ai_call`, {
      method: "POST",
      headers: { authorization: auth, apikey: key, "content-type": "application/json" },
      body: "{}",
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) { await res.body?.cancel(); return "unauthorized"; }
    return (await res.json()) === true ? "ok" : "rate_limited";
  } catch {
    return "unauthorized";
  }
}
