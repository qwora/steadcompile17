import SwiftUI

/// "Be careful" style pill.
struct LevelPill: View {
    let level: Level
    var large = false

    var body: some View {
        Label(level.title, systemImage: level.symbol)
            .font(large ? .headline : .caption.weight(.semibold))
            .foregroundStyle(level == .normal ? Theme.teal : .black)
            .padding(.horizontal, large ? 14 : 10)
            .padding(.vertical, large ? 8 : 5)
            .background(level == .normal ? Theme.teal.opacity(0.15) : level.color, in: Capsule())
    }
}

/// One message in a list.
struct EventRow: View {
    let event: MessageEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(event.isWarning ? event.level.color.opacity(0.18) : Theme.surfaceRaised)
                Image(systemName: event.appSymbol)
                    .foregroundStyle(event.isWarning ? event.level.color : Theme.muted)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.senderLabel).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    Text(event.receivedAt, style: .time).font(.caption).foregroundStyle(Theme.muted)
                }
                Text(event.body).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2)
                HStack(spacing: 8) {
                    if event.stage == .checking {
                        Label("Checking…", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(Theme.blue)
                    } else if event.rules.decision == .ignored {
                        Text(event.rules.ignoreReason ?? "Ignored").font(.caption).foregroundStyle(Theme.muted)
                    } else {
                        LevelPill(level: event.level)
                    }
                    if event.familyStatus != .none { FamilyStatusTag(status: event.familyStatus) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

struct FamilyStatusTag: View {
    let status: MessageEvent.FamilyStatus
    var body: some View {
        let (text, icon, color): (String, String, Color) = switch status {
        case .shared: ("Sent to family", "paperplane.fill", Theme.blue)
        case .checking: ("Family is checking", "eye.fill", Theme.amber)
        case .resolved: ("Resolved", "checkmark.seal.fill", Theme.teal)
        case .none: ("", "", .clear)
        }
        Label(text, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
    }
}

/// Section header used inside scroll views.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.title3.bold()).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// Example messages for trying Stead without waiting for a real scam. Links use .example domains.
enum Samples {
    struct Sample: Identifiable { let id = UUID(); let label: String; let app: String; let sender: String; let body: String }

    static let all: [Sample] = [
        Sample(label: "Fake road fine (Korean SMS)", app: "Messages", sender: "+82 10-5521-0937",
               body: "[국외발신] 도로 관리24: 미납 과태료 안내. 오늘까지 납부하지 않으면 가산금이 부과됩니다. https://sw.example/RJMkq"),
        Sample(label: "\"Mum, it's me\" new number", app: "WhatsApp", sender: "+60 11-2345 6789",
               body: "Mum it's me, my phone broke so this is my new number. Can you transfer RM2000 urgently? I'll pay you back tonight"),
        Sample(label: "Hacked friend's account", app: "WhatsApp", sender: "Cikgu Rahman",
               body: "Salam, please review the attached statement of account. Open it on a computer, it's not visible on mobile. Forward to your finance manager."),
        Sample(label: "Parcel fee", app: "Messages", sender: "+82 2-123-4567",
               body: "Your parcel is held at customs. Pay the ₩3,000 redelivery fee within 24 hours: https://bit.ly/parcel-example"),
        Sample(label: "Bank code (after a scam)", app: "Messages", sender: "KB Bank",
               body: "[KB] 인증번호 482913. 타인에게 절대 알려주지 마세요."),
        Sample(label: "Normal: dinner", app: "WhatsApp", sender: "Daniel",
               body: "Dinner at 7 tonight? I'll bring the kids 😊"),
    ]
}
