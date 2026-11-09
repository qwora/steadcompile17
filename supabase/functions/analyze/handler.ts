// Stead `analyze`: receives ONE flagged message and returns a structured assessment from Claude.
// Privacy: the message text is sent to Anthropic and then dropped. It is never stored or logged;
// logs carry only status, latency and the resulting category/level.
import { getUserId } from "../_shared/auth.ts";
import { anthropicBody, extractJson, validateAssessment, validateRequest } from "./lib.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function metric(fields: Record<string, unknown>) {
  console.log(JSON.stringify({ fn: "analyze", ...fields }));
}

export async function handle(req: Request, fetchFn: typeof fetch = fetch): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  if (!(await getUserId(req, fetchFn))) return json({ error: "unauthorized" }, 401);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const v = validateRequest(body);
  if (!v.ok) return json({ error: v.error }, v.status);

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "not_configured" }, 503);

  const started = Date.now();
  let resp: Response;
  try {
    resp = await fetchFn("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify(anthropicBody(v.req)),
      signal: AbortSignal.timeout(8000), // the app gives up at 10 s
    });
  } catch (e) {
    const timeout = e instanceof DOMException && (e.name === "TimeoutError" || e.name === "AbortError");
    metric({ status: timeout ? "timeout" : "network_error", ms: Date.now() - started });
    return json({ error: timeout ? "ai_timeout" : "ai_unavailable" }, 504);
  }
  if (!resp.ok) {
    await resp.body?.cancel();
    metric({ status: "api_error", http: resp.status, ms: Date.now() - started });
    return json({ error: "ai_unavailable" }, 502);
  }

  let assessment;
  try {
    assessment = validateAssessment(extractJson(await resp.json()), v.req.text);
  } catch {
    assessment = null;
  }
  if (!assessment) {
    metric({ status: "invalid_model_output", ms: Date.now() - started });
    return json({ error: "invalid_model_output" }, 502);
  }
  metric({ status: "ok", ms: Date.now() - started, category: assessment.category, concern: assessment.concern_level });
  return json(assessment);
}
