# Stead: Architecture and Build Plan

> c0mpiled-17 Seoul · Track: AI for the Aging Population · 9 Nov 2026, 10:00–15:00 KST
> **Stead. Safer, together.** An iPhone app that notices scam messages for older adults and brings family in before money moves.

Judged on **market, polish, presentation**. Every phase below ends with something demoable.

---

## 1. The product in one picture

```
 Mum's iPhone                                   Cloud                         Daniel's iPhone
 ─────────────────────────────────────────────  ────────────────────────────  ─────────────────────
 SMS / WhatsApp / any app notification
   │  iOS 27 Shortcuts "When I receive a notification"
   ▼
 CheckMessageIntent  (background, ~1 s)
   ├─ Clean text (NFKC, zero-width chars)
   ├─ Rules engine  → score + signals
   ├─ Thread tracker → per-sender score, bank-OTP-after-scam
   │
   ├─ score < 3 ─► log "Looks normal", silent (text never leaves phone)
   │
   └─ score ≥ 3 ─► notify "Taking a closer look…"
                   POST /analyze (flagged text only) ──►  Edge Function `analyze`
                                                          └─ Claude (structured JSON)
                   ◄── validated JSON ──────────────────┘   no text stored, no logs
                   Policy (deterministic) → Level 1/2/3
                   notify "Be careful · Possible fake fine"  (+ read aloud)
                   │
                   ├─ Level 1: Mum decides → "Ask Daniel"
                   ├─ Level 2: auto heads-up (if Mum consented)
                   └─ Level 3: urgent "Call Mum now"
                        │
                        ▼
                   insert `cases` row ─────────────────►  Supabase Postgres + RLS ──► Realtime ──► Guardian mode
                                                                                                   "I'm checking"
                   ◄──────────────── status update ◄─────────────────────────────────────────────── "Resolved"
                   Mum sees "Daniel is checking"
```

**Privacy line for the pitch:** normal messages never leave the phone. Flagged text is analysed and discarded. Family sees a short summary, never the chat.

---

## 2. Stack decisions

| Layer | Choice | Why |
|---|---|---|
| App | SwiftUI, iOS 27 target, one app with two modes | Already proven on device last night (knowledge, not code) |
| Bundle / ASC | `com.qawi.stead`, team `K4YMM5LT8Z`, ASC app `6832253425`, **v1.0 build 3+** | TestFlight already set up |
| Backend | **Supabase only**: Postgres + RLS, Anonymous Auth, Realtime, Edge Function | One platform: database, auth, live updates and the AI route |
| AI | Anthropic Messages API, **Claude Haiku 5.5** (`claude-haiku-5-5`), structured JSON output; Sonnet 5.5 as an option if latency allows | Fast enough for the ~10 s background window |
| Secrets | `ANTHROPIC_API_KEY` only in Supabase function secrets. Supabase URL + anon key in the app (safe with RLS) | Key never ships in the app |
| Swift packages | `supabase-swift` (auth, database, realtime) | Official client |
| Project generation | Hand-written `project.pbxproj` (objectVersion 77, synchronized folders) | No xcodegen on this Mac |

---

## 3. iOS app architecture

```
Stead/
  App/            SteadApp, Router (deep links from notifications), AppDelegate (notification delegate)
  Intake/         CheckMessageIntent, SteadShortcuts (App Shortcuts), PasteCheck
  Engine/
    TextCleaner     NFKC, zero-width detection (body only; ignore bidi marks)
    RulesEngine     signals + score (spec in handoff §5)
    ThreadTracker   per-sender rolling score (decays ~2 h), bank-OTP-after-flag detector
    Policy          rules + AI → Level 0–3 (deterministic)
    Pipeline        dedupe → ignore list → rules → thread → notify → analyze → policy → notify → escalate
  Services/
    AnalyzeClient   POST /analyze, 10 s timeout, schema validation
    CircleService   anon sign-in, create/join circle, members
    CaseService     create/update cases, Realtime subscription, refetch on foreground/reconnect/push tap (60 s only while disconnected)
    Notifier        local notifications (timeSensitive for Level 2–3), categories + actions
    Speaker         AVSpeechSynthesizer, reads the warning in Korean / English / Malay
  Store/          EventStore (local JSON in Application Support): every message event + result
  UI/
    Protected/    Home (kitten + status), MessageCheck, Activity, AskFamily sheet
    Guardian/     CaseList, CaseDetail ("I'm checking", "Call", "Resolved"), VerifyPrompt ("Was this you?")
    Onboarding/   ModePicker, CreateCircle / JoinCircle (6-digit code), ShortcutsGuide, Consent
    Kitten/       Native Canvas kitten (states: watching, taking a look, covering, sleeping, happy)
    Theme         Veil theme: black, teal #12C2A8, amber #FFB020
```

### Escalation levels (Policy)

| Level | Trigger | Mum | Daniel |
|---|---|---|---|
| 0 Normal | rules score < 3, or AI `looks_normal` and rules < 6 | Silent log | Nothing |
| 1 Worth a look | AI `worth_a_look`, or AI failed (shown as "Preliminary") | Warning + **Ask Daniel** button | Only if Mum taps |
| 2 Be careful | AI `be_careful` **and** asks for money / code / install / pay-link | Warning + read aloud | Auto heads-up if Mum consented |
| 3 Urgent | Thread score ≥ 8 from one sender in 30 min, **or** bank OTP / transfer / new-login message within 15 min of a Level ≥ 2 thread | Full-screen pause card: "Wait. Call Daniel." | Urgent: "Call Mum now" |

Floors: rules score ≥ 6 never goes below Level 1. A saved contact never lowers the level.

### "Was this you?" (family impersonation)
If the AI category is `family_impersonation` (new number, "Mum it's me"), Stead creates a `verify_identity` case aimed at the family members in the circle. Daniel taps **Yes, it's me** or **No, not me**. "No" turns Mum's screen into "Daniel says this isn't him. Don't reply."

---

## 4. Backend

### Edge Function `analyze` (POST, requires a signed-in Supabase user)

Request:
```json
{ "app": "WhatsApp", "sender_kind": "contact|number|email|unknown", "text": "…",
  "rule_signals": ["link", "payment"], "thread_count": 2, "locale": "ko" }
```
Response (validated server-side, re-validated in app):
```json
{
  "category": "government_impersonation | bank_impersonation | delivery_scam | family_impersonation | investment_scam | account_takeover | romance | job_scam | other | not_a_scam",
  "concern_level": "be_careful | worth_a_look | looks_normal",
  "asks_for": ["money", "code", "install", "link", "personal_info", "none"],
  "claimed_identity": "Korean road authority",
  "requested_action": "pay a fine through a link",
  "scam_stage": "hook | trust | pressure | ask | none",
  "explanation_for_user": "≤160 chars, calm, plain, in the user's language",
  "summary_for_guardian": "≤200 chars, no full message, no links",
  "recommended_verification": "Look up fines in the official government app.",
  "uncertainties": ["We can't check whether a fine really exists."]
}
```
Rules for the function: fixed system prompt, message text wrapped as untrusted data, no URL fetching, no invented verification, no storage or logging of message text. Errors return `{ "error": … }` and the app falls back to "Preliminary".

### Database (Postgres + RLS)

```sql
circles  (id uuid pk, name text, invite_code text unique, code_expires_at timestamptz, created_at)
members  (id uuid pk, circle_id fk, user_id uuid = auth.uid(), role text check in ('protected','guardian'),
          display_name text, kitten_color text, auto_share boolean default true, created_at,
          unique (circle_id, user_id))
cases    (id uuid pk, circle_id fk, protected_member_id fk, kind text check in ('warning','verify_identity'),
          level int, category text, sender_label text, claimed_identity text, requested_action text,
          summary_for_guardian text, recommended_verification text,
          status text check in ('open','checking','resolved') default 'open',
          handled_by uuid null, resolution text null,
          verify_target_member_id uuid null, verify_answer text null check in ('yes','no'),
          created_at, updated_at)
```
- **No raw message text anywhere in the database.**
- RLS: a user can read/write rows only where `is_member(circle_id)`. Guardians can update `status`, `handled_by`, `resolution`, `verify_answer`; only the protected member inserts cases.
- RPCs (security definer): `create_circle(display_name, role, name)` → returns code; `join_circle(code, display_name, role)` → checks code and expiry (zero rows = rejected, failed tries limited), inserts the member; `register_device` / `unregister_device` for APNs tokens.
- Realtime enabled on `cases` and `members`. APNs push via the `notify` function, fired by a trigger on `cases` (see BACKEND_TASKS.md §4).

---

## 5. Phases

Times are targets. **Feature freeze 13:45.** Each phase ends with a commit and a check on a real phone.

### Phase 0 · Foundations (10:10–10:40)
- Xcode project from scratch: bundle, team, iOS 27, icon, `ITSAppUsesNonExemptEncryption = NO`, v1.0 build 3, Veil theme.
- Supabase project, migration (tables, RLS, RPCs, Realtime), anonymous auth on.
- `analyze` function deployed returning a stub.
- README skeleton, first commit, push.
- **Done when:** app runs on the iPhone; `curl` to `/analyze` answers.

### Phase 1 · On-device pipeline (10:40–11:30)
- CheckMessageIntent + App Shortcut, TextCleaner, RulesEngine with the full test set (unit tests), ThreadTracker, EventStore, Notifier.
- Home (kitten + counts), Activity list, Shortcuts setup guide, paste check.
- **Done when:** a real SMS and WhatsApp produce the right alert with the app closed, and every rules test passes.

### Phase 2 · AI (11:30–12:15)
- Prompt + schema in `analyze`, Claude call, validation, error handling.
- AnalyzeClient + Policy in the app; second notification; MessageCheck screen (why, what we can't confirm, safe next step); read aloud.
- **Done when:** the Korean fine SMS and the teacher WhatsApp show a correct AI explanation within ~5 s; killing the network shows "Preliminary".

### Phase 3 · Family circle (12:15–13:15)
- Onboarding: mode picker, create circle (6-digit code) / join circle, consent toggle.
- Guardian mode: live case list + case detail with "I'm checking", "Call", "Resolved".
- Protected side: "Ask Daniel", auto-share for Level 2, status shown back to Mum.
- Level 3 (thread + bank-OTP-after-scam) and "Was this you?".
- **Done when:** two phones run the full loop twice in a row.
- **Fallback at 12:45:** if pairing breaks, a seeded demo circle (clearly labelled).

### Phase 4 · Ship + polish (13:15–13:45)
- TestFlight build (1.0, build 3+), install on both phones.
- Kitten states wired to levels, empty states, wording pass (no "High risk", no percentages).
- Two clean full rehearsals.

### Phase 5 · Pitch (13:45–14:45), then submit by 15:00
- 90 s video (both phone screens + narration), README with architecture, privacy, market data.
- Submit GitHub URL + video. **No new features after 13:45.**

### Stretch (only if a phase finishes early)
1. Share extension: share text or a **screenshot** to Stead (Vision OCR) — the answer for phones without iOS 27.
2. Daniel's 10-second voice note that plays on Mum's Level 2–3 warning.
3. Family code word reminder on impersonation warnings.
4. ~~APNs push to the guardian when their app is closed~~ backend built (`notify`); iOS registration still to do.
5. Weekly summary for the family.

---

## 6. Demo script (90 s)

| Time | Shot | Line |
|---|---|---|
| 0:00 | Mum's phone; 국외발신 "road fine" SMS arrives | "The scams that work are the ones that make sense in the moment." |
| 0:10 | Stead alert on the lock screen, read aloud | "Mum never opened an app. Stead noticed." |
| 0:20 | Message check screen | "AI explains the warning signs, and what it can't know." |
| 0:35 | WhatsApp "Mum, it's me, new number" → Daniel gets "Was this you?" → taps No | "Scammers know the family titles. Stead asks the family." |
| 0:55 | Bank OTP SMS arrives right after → Level 3 → Daniel: "Call Mum now" | "When it looks like she's about to pay, family steps in." |
| 1:10 | Normal message, silently skipped; privacy graphic | "Normal messages stay on the phone." |
| 1:20 | Kitten + logo | "Stead. Safer, together." |

## 7. Market lines for the pitch (verify before the slide)
- Korea 2025: ₩1.2578T (~US$870M) lost to voice phishing, 23,360 cases, a record; 78.6% from bank/authority impersonation.
- Victims aged 50+: 32% (2023) → 53% (Q1 2025).
- Scam texts to people in their 60s–70s use the right family title 96–97% of the time.
- Korea is super-aged: 10.51M people 65+ (20.3%); 96% of people in their 60s own a smartphone.
- Samsung protects Galaxy calls in Korea. Nobody protects Mum's iPhone across every messaging app, and nobody brings family in before money moves.
- Average loss ≈ ₩54M per case → one stopped scam pays for ~900 years of a ₩4,900/month family plan.

## 8. Ground rules
- No code from `~/Projects/stead-probe` (written before the event). Rebuild from specs.
- Never commit secrets (`.p8`, API keys, `.env`).
- Test messages use `.example` links, never real scam links.
- Say clearly what is simulated or seeded.
