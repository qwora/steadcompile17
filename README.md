# Stead

**Safer, together.** Stead is an iPhone app that spots scam messages for older adults and brings family in before money moves.

Scams on older people work by rushing them: a "fine" to pay now, a "son" on a new number who needs money today. Stead checks incoming messages, explains the risk in one plain sentence (Korean, English or Malay), and when it's serious, tells the family and gives the person a moment to stop and call someone they trust.

Built at c0mpiled-17 Seoul (9 Nov 2026), track **AI for the Aging Population**.

---

## Try it in 2 minutes (one phone)

1. **Install** Stead from TestFlight (ask the team for an invite) and open it.
2. **Set up:** tap **Get started**, enter the name your family calls you, and **Allow alerts and finish**.
3. **Check a message:** on Home, tap **Check a message**, paste one of the texts below, and tap **Check this message**.

| Paste this | What Stead should say |
|---|---|
| `[국외발신] 도로 관리24: 미납 과태료 확인 https://sw.example/xyz` | **Be careful**: a fake road fine asking you to pay through a link |
| `Hi Mum, this is my new number, my old phone broke. Can you help me pay a bill today? I'll explain later, can't talk right now.` | **Be careful**: someone pretending to be family, asking for money |
| `Guaranteed 30% monthly returns, join our investment group` | **Be careful**: an investment scam |
| `Dinner at 7 tonight?` | **Looks normal** |

Tap the speaker button on a result to hear it read aloud.

## The family demo (two phones)

| Step | Mum's phone | Daniel's phone |
|---|---|---|
| 1. Pair | **Family** → **Add family member** → "Daniel" → show the QR | **Family** → **Scan family QR** |
| 2. A scam arrives | Check the road-fine text above | Gets a push: Mum got a suspicious message |
| 3. Family helps | Sees "Daniel is checking" | Opens it → **I'm checking** → **Mark as handled** |
| 4. Family code | A message "from Daniel" asks for money → Stead asks for Daniel's **family code** | Opens his code with Face ID and reads it to Mum |
| 5. Wrong code | Enters a wrong code → "This may not be Daniel" | Gets an **urgent** alert to call Mum |

Everyone is protected: Daniel's own messages are checked too, and Mum is told about his.

## Key features

- **Automatic checks.** An iOS Shortcuts automation hands each new SMS or WhatsApp notification to Stead in the background. Set it up in **Settings → Set up automatic checks**.
- **Plain answers.** One sentence on what the message wants and why that's risky, plus one safe next step ("Call your son on the number you already have").
- **Family circle.** Family members get a short summary (never the chat) and can reply "I'm checking".
- **Family code.** A rotating 6-digit code that only the real family member can open with Face ID. It beats "Mum, it's me on a new number" scams, even from a hacked account.
- **Safety pause.** An urgent message opens a full-screen "Wait. Take a moment." screen: a 20-second pause, read aloud, with a big **Call Daniel** button. The person can always continue afterwards, and can turn it off in Settings.
- **The user stays in control.** **Settings** choose when to be warned and whether the family hears about serious messages.

## Privacy

- Normal messages never leave the phone. Only messages with warning signs are sent to the AI.
- The server never stores or logs message text. Family see only a short summary.
- Stead reads only what the notification shows. It never opens links or files.

## How it works

```
Message ──► on-phone rules ──► normal? stays on the phone
                 │
                 └─ warning signs ──► Supabase Edge Function ──► Claude Haiku 5.5 (structured JSON)
                                            │
                       Stead warns the user ◄┘──► family circle (Postgres + row-level security,
                                                   Realtime, Apple push)
```

| Part | Tech |
|---|---|
| App | SwiftUI, iOS 27, App Intents (Shortcuts) |
| Backend | Supabase: Postgres with row-level security, anonymous sign-in, Realtime, Edge Functions |
| AI | Anthropic Claude Haiku 5.5, structured output, prompt-injection safe, 8 s timeout |
| Alerts | Apple Push Notifications from the `notify` Edge Function |

## Repo layout

| Path | What |
|---|---|
| `Stead/` | The iOS app |
| `supabase/migrations/` | Database tables and access rules |
| `supabase/functions/analyze/` | AI scam check |
| `supabase/functions/notify/` | Family push alerts |
| `supabase/tests/` | Permission tests |
| `docs/` | [Plan](docs/PLAN.md), [backend details](docs/BACKEND_TASKS.md), [developer handoff](docs/HANDOFF.md) |

## For developers

Open `Stead.xcodeproj` in Xcode and run on an iPhone. The backend is already live; see [docs/HANDOFF.md](docs/HANDOFF.md) for setup and tests.
