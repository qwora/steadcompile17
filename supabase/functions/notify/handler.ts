// `notify`: called by the cases_notify trigger (pg_net) with { case_id, event } and a shared secret.
// Looks the case up with the service role, decides recipients (consent + level rules in lib.ts),
// claims (case, event) in push_log so each push goes out at most once, and sends via APNs.
import { apnsJwt, apnsPayload, type CaseEvent, type CaseRow, EVENTS, isDeadToken, type MemberRow, planPush, safeEqual } from "./lib.ts";

type Deps = { fetch: typeof fetch; now: () => number };
const json = (body: unknown, status = 200) => Response.json(body, { status });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

let cachedJwt: { token: string; at: number } | null = null;

export async function handle(req: Request, deps: Deps = { fetch, now: Date.now }): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const env = (k: string) => Deno.env.get(k) ?? "";
  const secret = env("NOTIFY_SECRET");
  if (!secret || !safeEqual(req.headers.get("x-stead-secret") ?? "", secret)) return json({ error: "unauthorized" }, 401);

  let body: { case_id?: unknown; event?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const caseId = String(body.case_id ?? "");
  const event = body.event as CaseEvent;
  if (!UUID.test(caseId) || !EVENTS.includes(event)) return json({ error: "invalid_body" }, 400);

  const [p8, keyId, teamId, topic] = ["APNS_AUTH_KEY", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_BUNDLE_ID"].map(env);
  if (!p8 || !keyId || !teamId || !topic) return json({ error: "apns_not_configured" }, 503);

  const base = env("SUPABASE_URL"), sr = env("SUPABASE_SERVICE_ROLE_KEY");
  const db = (path: string, init: RequestInit = {}) =>
    deps.fetch(`${base}/rest/v1/${path}`, {
      ...init,
      headers: { apikey: sr, authorization: `Bearer ${sr}`, "content-type": "application/json", ...init.headers },
    });

  const caseRes = await db(`cases?id=eq.${caseId}&select=id,circle_id,kind,level,requested_by_user,protected_member_id,verify_target_member_id,handled_by`);
  const [c] = caseRes.ok ? await caseRes.json() as (CaseRow & { circle_id: string })[] : [];
  if (!c) return json({ error: "case_not_found" }, 404);
  const members: MemberRow[] = await (await db(`members?circle_id=eq.${c.circle_id}&select=id,role,display_name,auto_share`)).json();

  // Recipients come only from this case's circle.
  const plan = planPush(c, event, members);
  if (!plan || plan.recipients.length === 0) return json({ sent: 0, reason: "no_push_for_this_event" });

  const claim = await db("push_log", {
    method: "POST",
    headers: { prefer: "resolution=ignore-duplicates,return=representation" },
    body: JSON.stringify({ case_id: caseId, event }),
  });
  if (!claim.ok) return json({ error: "claim_failed" }, 500);
  if ((await claim.json()).length === 0) return json({ sent: 0, reason: "duplicate" });

  const tokens: { device_token: string; environment: string }[] =
    await (await db(`device_tokens?member_id=in.(${plan.recipients.join(",")})&select=device_token,environment`)).json();

  const nowSec = Math.floor(deps.now() / 1000);
  if (!cachedJwt || nowSec - cachedJwt.at > 50 * 60) cachedJwt = { token: await apnsJwt(p8, keyId, teamId, nowSec), at: nowSec };
  const payload = JSON.stringify(apnsPayload(plan, caseId, event));

  let sent = 0, failed = 0, removed = 0;
  await Promise.all(tokens.map(async (t) => {
    const host = t.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    try {
      const res = await deps.fetch(`https://${host}/3/device/${t.device_token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${cachedJwt!.token}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-collapse-id": `${caseId}:${event}`.slice(0, 64),
          "content-type": "application/json",
        },
        body: payload,
        signal: AbortSignal.timeout(5000),
      });
      if (res.ok) { sent++; await res.body?.cancel(); return; }
      failed++;
      const reason = (await res.json().catch(() => ({})))?.reason as string | undefined;
      if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") cachedJwt = null;
      if (isDeadToken(res.status, reason)) {
        await db(`device_tokens?device_token=eq.${t.device_token}`, { method: "DELETE" });
        removed++;
      }
      console.log(JSON.stringify({ fn: "notify", apns: res.status, reason }));
    } catch {
      failed++;
    }
  }));
  // Every send failed (e.g. APNs outage): release the claim so a re-delivery of this event can retry.
  if (sent === 0 && failed > 0) await db(`push_log?case_id=eq.${caseId}&event=eq.${encodeURIComponent(event)}`, { method: "DELETE" });
  console.log(JSON.stringify({ fn: "notify", event, sent, failed, removed }));
  return json({ sent, failed, removed });
}
