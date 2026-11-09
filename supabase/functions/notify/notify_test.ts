// Offline push tests. APNs and PostgREST are SIMULATED with a mock fetch; no real device is involved.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { handle } from "./handler.ts";
import { apnsJwt, apnsPayload, type CaseRow, isDeadToken, type MemberRow, planPush } from "./lib.ts";

const mum: MemberRow = { id: "m-mum", role: "protected", display_name: "Mum", auto_share: true };
const dan: MemberRow = { id: "m-dan", role: "guardian", display_name: "Daniel", auto_share: true };
const sis: MemberRow = { id: "m-sis", role: "guardian", display_name: "Sara", auto_share: true };
const base: CaseRow = { id: "c1", kind: "warning", level: 2, requested_by_user: false, protected_member_id: "m-mum",
  verify_target_member_id: null, handled_by: null };
const fam = [mum, dan, sis];

Deno.test("level rules and consent", () => {
  assertEquals(planPush({ ...base, level: 0 }, "created", fam), null, "level 0: no push");
  assertEquals(planPush({ ...base, level: 1 }, "created", fam), null, "level 1: no automatic push");
  assertEquals(planPush({ ...base, level: 1, requested_by_user: true }, "created", fam)?.recipients, ["m-dan", "m-sis"], "level 1 when asked");
  assertEquals(planPush(base, "created", fam)?.recipients, ["m-dan", "m-sis"], "level 2 with consent");
  assertEquals(planPush(base, "created", [{ ...mum, auto_share: false }, dan]), null, "level 2 without consent");
  assert(planPush({ ...base, requested_by_user: true }, "created", [{ ...mum, auto_share: false }, dan]), "level 2 asked overrides");
  const urgent = planPush({ ...base, level: 3 }, "created", [{ ...mum, auto_share: false }, dan])!;
  assert(urgent.urgent && urgent.title === "STEAD — Urgent family alert", "level 3 urgent");
});

Deno.test("verify_identity goes to the named guardian; answers go back to the protected person", () => {
  const v = { ...base, kind: "verify_identity" as const, verify_target_member_id: "m-dan" };
  assertEquals(planPush(v, "created", fam)?.recipients, ["m-dan"]);
  assertEquals(planPush({ ...v, verify_target_member_id: null }, "created", fam)?.recipients, ["m-dan", "m-sis"]);
  const no = planPush(v, "verify:no", fam)!;
  assertEquals(no.recipients, ["m-mum"]);
  assert(no.urgent && no.body.startsWith("Daniel says"));
  assertEquals(planPush({ ...base, handled_by: "m-dan" }, "status:checking", fam)?.body.startsWith("Daniel is checking"), true);
});

Deno.test("recipients never include people outside the circle's member list", () => {
  const p = planPush({ ...base, kind: "verify_identity", verify_target_member_id: "m-stranger" }, "created", fam)!;
  assertEquals(p.recipients, ["m-dan", "m-sis"]);
});

Deno.test("payload is generic", () => {
  const p = apnsPayload(planPush(base, "created", fam)!, "c1", "created");
  assertEquals(Object.keys(p).sort(), ["aps", "case_id", "event"]);
  assertEquals(p.aps.alert.title, "STEAD — Please check on Mum");
});

Deno.test("APNs JWT is a valid ES256 signature", async () => {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\\n${btoa(String.fromCharCode(...der))}\\n-----END PRIVATE KEY-----`; // escaped \n, as in a secret
  const jwt = await apnsJwt(pem, "KEY123", "TEAM456", 1_700_000_000);
  const [h, c, s] = jwt.split(".");
  const dec = (x: string) => JSON.parse(atob(x.replace(/-/g, "+").replace(/_/g, "/")));
  assertEquals(dec(h), { alg: "ES256", kid: "KEY123" });
  assertEquals(dec(c), { iss: "TEAM456", iat: 1_700_000_000 });
  const sig = Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - s.length % 4) % 4)), (x) => x.charCodeAt(0));
  assertEquals(sig.length, 64);
  assert(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, kp.publicKey, sig, new TextEncoder().encode(`${h}.${c}`)));
  Deno.env.set("APNS_AUTH_KEY", pem);
});

Deno.test("dead token detection", () => {
  assert(isDeadToken(410, "Unregistered"));
  assert(isDeadToken(400, "BadDeviceToken"));
  assert(!isDeadToken(400, "DeviceTokenNotForTopic"));
  assert(!isDeadToken(429, "TooManyRequests"));
});

// ── handler with simulated PostgREST + APNs ─────────────────────────────
const CASE = "11111111-1111-4111-8111-111111111111";
const GOOD = "ab".repeat(32), DEAD = "cd".repeat(32);
for (const [k, v] of Object.entries({ NOTIFY_SECRET: "s3cret", APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_BUNDLE_ID: "com.qawi.stead",
  SUPABASE_URL: "https://db.example", SUPABASE_SERVICE_ROLE_KEY: "service" })) Deno.env.set(k, v);

function world(caseRow: CaseRow & { circle_id: string }, onlyDead = false) {
  const claimed = new Set<string>();
  const released: string[] = [];
  const pushes: { url: string; headers: Headers; body: unknown }[] = [];
  const deleted: string[] = [];
  const f = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.includes("/rest/v1/cases?")) return Response.json([caseRow]);
    if (url.includes("/rest/v1/members?")) {
      assert(url.includes(`circle_id=eq.${caseRow.circle_id}`));
      return Response.json(fam);
    }
    if (url.endsWith("/rest/v1/push_log")) {
      const b = JSON.parse(String(init!.body)); const k = b.case_id + b.event;
      if (claimed.has(k)) return Response.json([]);
      claimed.add(k); return Response.json([b]);
    }
    if (url.includes("/rest/v1/push_log?") && init?.method === "DELETE") { released.push(url); return new Response(null, { status: 204 }); }
    if (url.includes("/rest/v1/device_tokens?member_id=in.")) {
      if (onlyDead) return Response.json([{ device_token: DEAD, environment: "production" }]);
      return Response.json([{ device_token: GOOD, environment: "sandbox" }, { device_token: DEAD, environment: "production" }]);
    }
    if (url.includes("/rest/v1/device_tokens?device_token=eq.")) { deleted.push(url.split("eq.")[1]); return new Response(null, { status: 204 }); }
    if (url.startsWith("https://api.")) {
      pushes.push({ url, headers: new Headers(init!.headers), body: JSON.parse(String(init!.body)) });
      return url.includes(DEAD) ? Response.json({ reason: "Unregistered" }, { status: 410 }) : new Response(null, { status: 200 });
    }
    throw new Error("unexpected " + url);
  }) as typeof fetch;
  return { f, pushes, deleted, released };
}
const call = (f: typeof fetch, event = "created", secret = "s3cret") =>
  handle(new Request("http://x/notify", { method: "POST", headers: { "x-stead-secret": secret }, body: JSON.stringify({ case_id: CASE, event }) }),
    { fetch: f, now: () => 1_700_000_000_000 });

Deno.test("handler: wrong secret → 401", async () => {
  const w = world({ ...base, id: CASE, circle_id: "circ" });
  assertEquals((await call(w.f, "created", "nope")).status, 401);
  assertEquals(w.pushes.length, 0);
});

Deno.test("handler: sends once, removes the dead token, ignores the duplicate", async () => {
  const w = world({ ...base, id: CASE, level: 3, circle_id: "circ" });
  const r1 = await (await call(w.f)).json();
  assertEquals(r1, { sent: 1, failed: 1, removed: 1 });
  assertEquals(w.deleted, [DEAD]);
  const sandbox = w.pushes.find((p) => p.url.includes("api.sandbox.push.apple.com"))!;
  assertEquals(sandbox.headers.get("apns-topic"), "com.qawi.stead");
  assertEquals(sandbox.headers.get("apns-push-type"), "alert");
  assert(sandbox.headers.get("authorization")!.startsWith("bearer "));
  assertEquals((sandbox.body as { aps: Record<string, string> }).aps["interruption-level"], "time-sensitive");
  assert(!JSON.stringify(sandbox.body).includes("summary"), "no case summary in the push");

  const r2 = await (await call(w.f)).json();
  assertEquals(r2, { sent: 0, reason: "duplicate" });
  assertEquals(w.pushes.length, 2, "duplicate event made no new pushes");
});

Deno.test("handler: level 2 without consent sends nothing", async () => {
  const w = world({ ...base, id: CASE, circle_id: "circ" });
  const f = (async (i: string | URL | Request, init?: RequestInit) =>
    String(i).includes("/rest/v1/members?") ? Response.json([{ ...mum, auto_share: false }, dan]) : w.f(i, init)) as typeof fetch;
  assertEquals(await (await call(f)).json(), { sent: 0, reason: "no_push_for_this_event" });
  assertEquals(w.pushes.length, 0);
});

Deno.test("handler: unknown event rejected", async () => {
  const w = world({ ...base, id: CASE, circle_id: "circ" });
  assertEquals((await call(w.f, "status:open")).status, 400);
});

Deno.test("handler: when every send fails the claim is released for a retry", async () => {
  const w = world({ ...base, id: CASE, level: 3, circle_id: "circ" }, true);
  assertEquals(await (await call(w.f)).json(), { sent: 0, failed: 1, removed: 1 });
  assertEquals(w.released.length, 1);
});
