// Stead `analyze`: receives ONE flagged message and returns a structured assessment.
// Phase 0: stub that validates input and returns a fixed, clearly-labelled result.
// Phase 2 replaces `assess` with the Claude call. Message text is never stored or logged.

type AnalyzeRequest = {
  app?: string;
  sender_kind?: "contact" | "number" | "email" | "unknown";
  text: string;
  rule_signals?: string[];
  thread_count?: number;
  locale?: string;
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function assess(_req: AnalyzeRequest) {
  return {
    stub: true,
    category: "other",
    concern_level: "worth_a_look",
    asks_for: ["none"],
    claimed_identity: null,
    requested_action: null,
    scam_stage: "none",
    explanation_for_user: "Test response from Stead's server. The AI check is not connected yet.",
    summary_for_guardian: "Test case from Stead's server.",
    recommended_verification: "Check with family before acting.",
    uncertainties: ["This is a test response."],
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: AnalyzeRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (typeof body?.text !== "string" || body.text.trim().length === 0) return json({ error: "missing_text" }, 400);
  if (body.text.length > 4000) return json({ error: "text_too_long" }, 413);

  return json(assess(body));
});
