# Backend + AI (status, contracts, setup)

Everything here lives under `supabase/`. Full product context: [PLAN.md](PLAN.md) §3–4.
**Status legend:** ✅ built and tested offline · 🟡 built, needs a real project/device to verify · ⬜ not built.

| Piece | Status | Where |
|---|---|---|
| `analyze` (Claude Haiku 5.5) | ✅ offline tests · 🟡 live eval not yet run | `functions/analyze/` |
| Circles, members, cases + RLS | ✅ SQL tests (PGlite stand-in) · 🟡 run on real Supabase | `migrations/`, `tests/authorization_test.sql` |
| Device tokens + `notify` (APNs) | ✅ simulated APNs tests · 🟡 real device delivery | `migrations/…_harden_circles_and_push.sql`, `functions/notify/` |
| iOS side of circles/cases/push/Realtime | 🟡 written, **not yet compiled** (no Xcode on the machine it was written on) | `Stead/Services/CircleService.swift`, `Stead/UI/Guardian/CaseList.swift` |

---

## 1. Set up the Supabase project

1. Create a project (region **Seoul / Northeast Asia**).
2. Authentication → Sign In / Providers → turn on **Allow anonymous sign-ins**.
3. Database → Extensions: `pg_net` is enabled by the migration; Vault is on by default.
4. Link, migrate, set secrets, deploy:

```bash
npx supabase login
npx supabase link --project-ref <your-ref>
npx supabase db push

npx supabase secrets set ANTHROPIC_API_KEY=<key>
npx supabase functions deploy analyze

# APNs: Apple Developer → Keys → new key with "Apple Push Notifications service". Never commit the .p8.
npx supabase secrets set APNS_KEY_ID=<10-char key id> APNS_TEAM_ID=K4YMM5LT8Z APNS_BUNDLE_ID=com.qawi.stead
npx supabase secrets set APNS_AUTH_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
npx supabase secrets set NOTIFY_SECRET=<long random string, e.g. openssl rand -hex 32>
npx supabase functions deploy notify --no-verify-jwt   # caller is the DB trigger, checked by NOTIFY_SECRET
```

5. Tell the database where `notify` is (SQL editor, once). Use the same secret as `NOTIFY_SECRET`:

```sql
select vault.create_secret('https://<your-ref>.supabase.co/functions/v1/notify', 'stead_notify_url');
select vault.create_secret('<same value as NOTIFY_SECRET>', 'stead_notify_secret');
```

Until both exist, the trigger does nothing and case writes still succeed.

6. Put the **Project URL** and **anon key** in `Stead/App/Config.swift` (safe to commit; the service-role key, Anthropic key and `.p8` are not).
7. Check: Database → Publications → `supabase_realtime` contains `cases` and `members`.

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided to functions automatically.

---

## 2. `analyze` (POST `/functions/v1/analyze`)

- Requires a **signed-in user's** access token (`Authorization: Bearer <session token>`). The anon key alone gets `401` (the gateway accepts it, so the function checks itself via the `claim_ai_call` RPC).
- Budget: **60 calls per user per hour**, then `429`.
- Calls `claude-haiku-5-5` via the Messages API (`fetch`, `anthropic-version: 2023-06-01`), `output_config.format` = JSON schema, effort `low`, aborted after **8 s**.
- The message is fenced as untrusted data; instructions inside it are ignored by the system prompt, and the server re-checks the answer: every field present, enums valid, lengths, ≤ 3 uncertainties, and in every shown string no `%`, no link and no phone number taken from the message; the guardian summary may not quote the message (no shared run of 25+ characters), since it gets stored.
- **Never logs or stores the message text.** Logs are one JSON line: status, latency, category, level.

### Request (unchanged)

```json
{ "app": "WhatsApp", "sender_kind": "contact | number | email | unknown", "text": "≤ 4000 chars",
  "rule_signals": ["link", "payment"], "thread_count": 2, "locale": "ko | en | ms" }
```
Every field is required.

### Response 200 (unchanged; every field present, nullable ones as `null`)

```json
{ "category": "government_impersonation", "concern_level": "be_careful", "asks_for": ["money", "link"],
  "claimed_identity": "Korean road authority", "requested_action": "Pay a fine through a link",
  "scam_stage": "pressure", "explanation_for_user": "…", "summary_for_guardian": "…",
  "recommended_verification": "…", "uncertainties": ["…"] }
```

### Errors (the app falls back to `LocalAssessor`, marked Preliminary)

| Status | `error` |
|---|---|
| 400 | `invalid_json`, `invalid_body`, `missing_text`, `invalid_app`, `invalid_sender_kind`, `invalid_rule_signals`, `invalid_thread_count`, `invalid_locale` |
| 401 | `unauthorized` |
| 413 | `text_too_long` |
| 429 | `rate_limited` |
| 502 | `invalid_model_output`, `ai_unavailable` |
| 503 | `not_configured` |
| 504 | `ai_timeout`, `ai_unavailable` (network) |

---

## 3. Database

Tables: `circles`, `members`, `cases` (no message text, ever), plus `device_tokens`, `push_log`, `join_attempts`, `ai_calls` (user id + time only).

| Who | Can |
|---|---|
| Anyone not signed in | Nothing (RPCs revoked from `anon`) |
| Any member | Read their circle, its members and its cases. Update own `display_name`, `kitten_color`, `auto_share` only |
| Protected member | Insert cases for **themselves** (status `open`, unhandled, unanswered; `verify_target_member_id` must be a guardian in the circle). Change `status`/`resolution` |
| Guardian | Change `status`, `resolution`, `handled_by` (only to themselves), `verify_answer` (only on a `verify_identity` case aimed at them or at nobody, once) |
| Nobody (client) | Change a case's facts after insert; change their own role/circle; read anyone's device tokens; read `push_log` |

New column: `cases.requested_by_user boolean default false` — set `true` when the person taps **Ask family**.

### RPCs

| RPC | Returns | Notes |
|---|---|---|
| `create_circle(p_display_name, p_role='protected', p_name='Family')` | `circle_id, invite_code, member_id` | 6-digit code, valid 24 h |
| `join_circle(p_code, p_display_name, p_role='guardian')` | `circle_id, member_id` — **zero rows = invalid, used or expired code** | **Codes are single-use**: a new join expires it, so call `refresh_invite_code` to invite the next person. `'protected'` only if the circle has none yet. 10 failed tries / 15 min / user, then raises `too many attempts`. Re-joining keeps your role |
| `refresh_invite_code(p_circle)` | new code | members only |
| `register_device(p_member_id, p_token, p_environment='production')` | token row id | token = lowercase hex; `sandbox` for Xcode/debug builds, `production` for TestFlight/App Store |
| `unregister_device(p_token)` | — | only your own token |
| `claim_ai_call()` | boolean | used by `analyze`; not for the app |

---

## 4. Push (`notify`) and Realtime

```
case insert/update ──► trigger cases_notify ──pg_net──► notify (secret) ──► APNs ──► guardian / protected phone
        └────────────► Realtime (postgres_changes, RLS-filtered) ──► open app updates instantly
```

| Event | Who gets a push | Rule |
|---|---|---|
| case created, Level 1 | guardians | only if `requested_by_user` |
| case created, Level 2 | guardians | if `requested_by_user` or protected `auto_share` |
| case created, Level 3 | guardians | always, `time-sensitive` |
| `verify_identity` created | the target guardian (or all guardians if none) | same consent rule as its level |
| `status` → `checking` / `resolved` | protected member | "Daniel is checking…" |
| `verify_answer` set | protected member | `no` is `time-sensitive` |

- Each `(case, event)` is claimed in `push_log` first, so a repeated trigger sends nothing. If every send fails, the claim is released so a re-delivery can retry.
- Tokens APNs reports as `410` / `BadDeviceToken` / `Unregistered` are deleted.
- Payload: `{"aps":{"alert":{"title","body"},"sound":"default","interruption-level","thread-id":"stead-cases"},"case_id","event"}`. No summary, link, code or message content. The app fetches the case (RLS-checked) after opening.

---

## 5. iOS integration contract

**Implemented in `CircleService`** and wired into the family-code pairing:
- "Continue to pairing" / "Show pairing QR" creates the circle once, then puts a fresh single-use invite in the QR (`PairingPayload.invite`). The family-code secret stays on the phones.
- Scanning the QR on the guardian phone joins the circle under the name Mum gave them, asks for notification permission and registers the push token.
- `FamilyBridge` writes cases (`verify_identity` with the guardian as target when a family check is needed). A correct family code resolves the case; a wrong one creates a Level 3 case, so every guardian gets the urgent push.
- The guardian home shows live cases with "I'm checking", "Mark as handled" and "Yes, it's me / No, that's not me". Mum's message screen shows the answer.
- The push entitlement is `Stead.entitlements` (`aps-environment`), and refresh happens on foreground, push and Realtime change.

The snippets below are the underlying calls.

Requires: **Push Notifications** capability (`aps-environment` entitlement) on the app target. Snippets target supabase-swift 2.x (2.55.6 resolved).

**Circles**
```swift
struct Created: Decodable { let circle_id: UUID; let invite_code: String; let member_id: UUID }
let c: Created = try await client.rpc("create_circle", params: ["p_display_name": name]).single().execute().value

struct Joined: Decodable { let circle_id: UUID; let member_id: UUID }
let rows: [Joined] = try await client.rpc("join_circle", params: ["p_code": code, "p_display_name": name]).execute().value
guard let joined = rows.first else { /* show "That code didn't work or has expired" */ }
```
Sync the consent toggle: `Settings.autoShareSerious` → `update members set auto_share = … where id = myMemberID`.

**Creating a case** (in `FamilyBridge.share`; `summary_for_guardian` from the assessment, never the message):
```swift
try await client.from("cases").insert([
  "circle_id": circleID, "protected_member_id": memberID, "kind": kind,  // "verify_identity" for family_impersonation
  "level": event.level.rawValue, "category": a.category, "app": event.app,
  "claimed_identity": a.claimedIdentity, "requested_action": a.requestedAction,
  "summary_for_guardian": a.summaryForGuardian, "recommended_verification": a.recommendedVerification,
  "requested_by_user": askedFamily ]).execute()
```

**Device registration** (every launch after sign-in and when the token changes):
```swift
// AppDelegate: UIApplication.shared.registerForRemoteNotifications()
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
  let hex = token.map { String(format: "%02x", $0) }.joined()
  #if DEBUG
  let env = "sandbox"
  #else
  let env = "production"
  #endif
  Task { try? await client.rpc("register_device", params: ["p_member_id": memberID.uuidString, "p_token": hex, "p_environment": env]).execute() }
}
// On "leave circle"/sign-out: rpc("unregister_device", params: ["p_token": hex])
```

**Push tap → deep link**: in `userNotificationCenter(_:didReceive:)`, read `userInfo["case_id"]`, fetch `from("cases").select().eq("id", value: caseID).single()`, open the case screen. Remote pushes have no `categoryIdentifier`, so they won't collide with `Notifier.warningCategory`.

**Realtime** (guardian list and protected "family is checking" status):
```swift
let channel = client.channel("cases-\(circleID)")
let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "cases", filter: .eq("circle_id", value: circleID))
await channel.subscribe()
for await change in changes { await reloadCases() }   // insert = new case, update = status / answer / resolution
```
Recovery (instead of 3 s polling): refetch `cases where circle_id = … order by updated_at desc limit 50` **on app foreground, on channel (re)subscribe, and after a push tap**. If the channel stays unsubscribed, refetch every 60 s while the screen is visible, and stop once it reconnects.

---

## 6. Tests

| Test | Command | Needs |
|---|---|---|
| Function unit tests (21): validation, prompt fencing, 401/502/504 paths, no text in logs, push rules, consent, dedupe, dead-token removal, ES256 JWT | `deno test --allow-env supabase/functions` | nothing |
| Authorization (RLS/RPC) test, rolls back | `psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/authorization_test.sql` | local (`npx supabase start`) or real DB |
| Live AI eval, 8 cases from the brief | `SUPABASE_URL=… SUPABASE_ANON_KEY=… deno run --allow-net --allow-env supabase/functions/analyze/eval.ts` | deployed `analyze` + Anthropic key |
| Real push | Install a debug build on a guardian iPhone, register, create a Level 3 case from the protected phone | APNs key + device |

Use `.example` domains in test messages, never real scam links.

### Known limits
- Invite-code guessing is limited per user, and anonymous sign-ups are capped per IP by Supabase Auth; there's no per-IP limit of our own.
- pg_net doesn't retry: if APNs is down when a case is written, that push is lost (Realtime and the foreground refetch still deliver the update).
- A guardian on a `verify_identity` case with no target can answer for the circle. Single-use codes keep strangers out, but the protected person's app should show who answered.
- Display names show in pushes (1–40 chars, enforced). Members choose their own, so a member could pick a misleading one.
- A Level 3 case pushes regardless of `auto_share` (urgent by design); the app decides whether a Level 3 case is created when auto-share is off.
