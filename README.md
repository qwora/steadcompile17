# Stead

**Safer, together.** An iPhone app that notices scam messages for older adults and brings family in before money moves.

Built at c0mpiled-17 Seoul (9 Nov 2026), track **AI for the Aging Population**.

## How it works

1. A message arrives on SMS, WhatsApp or another app.
2. An iOS 27 Shortcuts automation ("When I receive a notification") hands it to Stead in about a second, with the app closed.
3. On-device rules decide whether it's worth a closer look. Normal messages never leave the phone.
4. Flagged messages go to a Supabase Edge Function that asks Claude for a structured, plain-language assessment.
5. Stead warns the user, and, depending on the level and the user's consent, alerts a family member in their circle, who can mark it "I'm checking" and "Resolved".

See [docs/PLAN.md](docs/PLAN.md) for the architecture, escalation levels and build phases.

## Repo layout

| Path | What |
|---|---|
| `Stead/` | SwiftUI iOS app |
| `supabase/migrations/` | Database: circles, members, cases, row-level security |
| `supabase/functions/analyze/` | Edge Function that calls the AI |
| `docs/` | Plan and architecture |

## Privacy

- Only messages with warning signs are sent for AI review; the server doesn't store message text.
- Family members see a short summary, never the conversation.
- Stead only reads what the notification shows. It never opens links or files.
