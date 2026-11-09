# STEAD backend handoff

You're picking up the backend and the iOS ↔ backend connection. Most of it is built, deployed and tested; four things are left (§3).
Full reference: [BACKEND_TASKS.md](BACKEND_TASKS.md) (setup, API contracts, push rules, iOS integration, known limits). Product: [PLAN.md](PLAN.md).

## 1. Get access (once)

1. Accept the Supabase invite to **Stead's organization** (check your email).
2. In the repo folder:
   ```bash
   npx supabase@3.0.0 login
   npx supabase@3.0.0 link --project-ref xdbvowflznhepcfmbrnj
   ```
   On Windows PowerShell, use `npx.cmd` if `npx` is blocked by the script policy.
3. For a local build you need Xcode, the Apple team `K4YMM5LT8Z`, and Deno only if you run the function tests (`npm i -g deno` or deno.land).

CLI 3.x notes: add `--remote` to `db push` / `db query` (it defaults to a local database). Never commit secrets, `.env` files or `.p8` keys.

## 2. What's live

| Piece | State |
|---|---|
| Supabase project `stead`, ref `xdbvowflznhepcfmbrnj`, **Seoul** | Healthy. Anonymous sign-in **on** |
| Database: 4 migrations in `supabase/migrations/` | Applied. Permission test passes on the live DB |
| Realtime | `cases`, `members` published |
| `analyze` function (Claude Haiku 5.5) | Deployed. **Waiting for `ANTHROPIC_API_KEY`** → returns `503 not_configured` until then |
| `notify` function (APNs) | Deployed (`--no-verify-jwt`). APNs secrets, `NOTIFY_SECRET` and both Vault entries set |
| Push trigger | Tested live: a new case reaches `notify` (200), deduped in `push_log` |
| Nightly cleanup (pg_cron `stead-cleanup`) | Cases > 30 days, rate-limit rows > 1 day |
| `Stead/App/Config.swift` | Points at the live project |
| iOS glue (`CircleService.swift`, `CaseList.swift`, pairing/settings edits) | **Written but never compiled** |

Secrets on the project (values not in the repo): `ANTHROPIC_API_KEY` (missing), `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_AUTH_KEY`, `NOTIFY_SECRET`. List them with `npx supabase@3.0.0 secrets list`.

## 3. Your to-do

1. **Claude key.** Ask the team for the key directly (not in chat or the repo), then:
   ```bash
   npx supabase@3.0.0 secrets set ANTHROPIC_API_KEY=sk-ant-…
   ```
   Check it with the live eval (22 messages, a few cents):
   ```bash
   SUPABASE_URL=https://xdbvowflznhepcfmbrnj.supabase.co SUPABASE_ANON_KEY=<anon key from Config.swift> deno run --allow-net --allow-env supabase/functions/analyze/eval.ts
   ```
   Last run (9 Nov): 21/22. Every category and level is correct; the one miss is the first call after a deploy (cold start, about 5–9 s). Later calls take 2–5 s. **Before a demo, run one check to warm it up.**
2. **Build in Xcode** and fix any compile errors. The likeliest spot is the supabase-swift 2.55 Realtime calls in `CircleService.subscribe()` (`postgresChange` filter, `subscribe()`). If the build complains about provisioning, enable **Push Notifications** for `com.qawi.stead` in the Apple Developer portal (entitlement: `Stead.entitlements`).
3. **Two-phone test.**
   - Mum: Family → add Daniel → show QR. Daniel: "Someone in my family" → Scan family QR.
   - Send Mum a test scam text, e.g. `[국외발신] 도로 관리24: 미납 과태료 확인 https://sw.example/xyz`.
   - Daniel should get a push → open → "I'm checking" → Mum sees "Daniel is checking".
   - Family-code path: a message from Daniel's contact asking for money → Mum enters a wrong code → Daniel gets "Urgent family alert".
4. **After the demo: rotate the APNs key.** Key `AZCKR2FVDG` was exposed in a chat session. Revoke it in the Apple Developer portal, create a new one, and update `APNS_KEY_ID` and `APNS_AUTH_KEY`. No code changes.

## 4. Testing

| Test | Command |
|---|---|
| Function unit tests (21, offline) | `deno test --allow-env supabase/functions` |
| Permission test on live DB (rolls back) | `npx supabase@3.0.0 db query --remote -f supabase/tests/authorization_test.sql` (no error = pass) |
| Live AI eval | see §3.1 |

## 5. Things to know

- **Invite codes are single-use.** Each new family member needs a fresh QR (the app makes one each time). An empty `join_circle` result means a wrong, used or expired code.
- **Guardians are matched by name** to Mum's family list (the name Mum typed). Two guardians with the same name will collide.
- **No polling while Realtime is down.** The app refetches on foreground, on push and on reconnect instead.
- **No way to leave a circle or remove a member yet**, and `unregister_device` is never called.
- **Level 3 always pushes**, regardless of the auto-share setting. Level 2 needs consent. Level 1 only when Mum taps "Ask family".
- **Family codes are one per direction.** Each phone shows its own code and checks the other phone's, so a scammer can't get someone to read a code off their own screen. Both demo phones must run the same build, because codes from older builds won't match.
- **Safety pause** (`PauseView.swift`): an urgent (Level 3) message first opens a full-screen "Wait. Take a moment." screen with a 20 s countdown, read aloud, and a "Call <family>" button using the number saved on the phone. After the countdown the person can always continue. It shows once per message, from a notification tap or on opening the app within 30 min. Settings → "Pause before urgent messages" turns it off. It doesn't block other apps; that would need Apple's Family Controls entitlement.
- **The message text is never stored or logged.** Keep it that way: cases hold only the AI's short summary.
