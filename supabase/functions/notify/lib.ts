// Pure logic for `notify`: who gets a push for a case event, what it says, and the APNs JWT.
// Pushes never carry message content: only a generic line, the person's display name and the case id.

export type CaseRow = {
  id: string;
  kind: "warning" | "verify_identity";
  level: number;
  requested_by_user: boolean;
  protected_member_id: string;
  verify_target_member_id: string | null;
  handled_by: string | null;
};
export type MemberRow = { id: string; role: "protected" | "guardian"; display_name: string; auto_share: boolean };
export type PushPlan = { recipients: string[]; title: string; body: string; urgent: boolean };

export const EVENTS = ["created", "status:checking", "status:resolved", "verify:yes", "verify:no"] as const;
export type CaseEvent = typeof EVENTS[number];

/**
 * Level 0: never a case. Level 1: push only if the person tapped "Ask family".
 * Level 2: push if they asked, or if they consented to automatic sharing (members.auto_share).
 * Level 3: always an urgent push. Everyone else in the circle is told; their actions push back to the person.
 */
export function planPush(c: CaseRow, event: CaseEvent, members: MemberRow[]): PushPlan | null {
  const byId = new Map(members.map((m) => [m.id, m]));
  const person = byId.get(c.protected_member_id);
  if (!person) return null;
  const name = person.display_name;

  if (event === "created") {
    if (c.level < 1) return null;
    const shared = c.level >= 3 || c.requested_by_user || (c.level === 2 && person.auto_share);
    if (!shared) return null;
    // Everyone protects everyone: every other member of the circle is told.
    const guardians = members.filter((m) => m.id !== c.protected_member_id).map((m) => m.id);
    if (c.kind === "verify_identity") {
      const target = c.verify_target_member_id && c.verify_target_member_id !== c.protected_member_id
        && byId.has(c.verify_target_member_id)
        ? [c.verify_target_member_id] : guardians;
      return { recipients: target, urgent: c.level >= 3, title: "STEAD — Was this you?",
        body: `Someone messaging ${name} says they're family. Open STEAD to answer.` };
    }
    if (c.level >= 3) {
      return { recipients: guardians, urgent: true, title: "STEAD — Urgent family alert",
        body: `Please contact ${name} now and check the latest alert.` };
    }
    return { recipients: guardians, urgent: false, title: `STEAD — Please check on ${name}`,
      body: "A suspicious message may involve a request for money or a code. Open STEAD to verify." };
  }

  const back = [c.protected_member_id];
  const helper = (c.handled_by && byId.get(c.handled_by)?.display_name) || "Your family";
  const target = (c.verify_target_member_id && byId.get(c.verify_target_member_id)?.display_name) || "Your family";
  switch (event) {
    case "status:checking":
      return { recipients: back, urgent: false, title: "STEAD", body: `${helper} is checking the message for you. Please wait before you reply.` };
    case "status:resolved":
      return { recipients: back, urgent: false, title: "STEAD", body: `${helper} has looked into the message. Open STEAD to see what they found.` };
    case "verify:no":
      return { recipients: back, urgent: true, title: "STEAD — It wasn't them",
        body: `${target} says that message was not from them. Don't reply or send money.` };
    case "verify:yes":
      return { recipients: back, urgent: false, title: "STEAD", body: `${target} says that message was from them.` };
  }
  return null;
}

export function apnsPayload(plan: PushPlan, caseId: string, event: CaseEvent) {
  return {
    aps: {
      alert: { title: plan.title, body: plan.body },
      sound: "default",
      "interruption-level": plan.urgent ? "time-sensitive" : "active",
      "thread-id": "stead-cases",
    },
    case_id: caseId,
    event,
  };
}

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const enc = new TextEncoder();

/** Provider token for APNs: ES256 JWT signed with the .p8 key (valid up to 60 min; we refresh at 50). */
export async function apnsJwt(p8: string, keyId: string, teamId: string, nowSec: number): Promise<string> {
  const pem = p8.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (ch) => ch.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const head = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = b64url(enc.encode(JSON.stringify({ iss: teamId, iat: nowSec })));
  // WebCrypto returns the raw r||s form that JWS ES256 expects.
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${head}.${claims}`)));
  return `${head}.${claims}.${b64url(sig)}`;
}

/** APNs says the token will never work again: remove it. */
export function isDeadToken(status: number, reason: string | undefined): boolean {
  return status === 410 || (status === 400 && (reason === "BadDeviceToken" || reason === "Unregistered"));
}

export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
