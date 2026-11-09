import SwiftUI

/// The explanation screen: what the message is, why Stead is worried, what it can't know, what to do.
struct MessageCheckView: View {
    let eventID: UUID
    @EnvironmentObject private var store: EventStore
    @StateObject private var speaker = Speaker.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let event = store.event(id: eventID) { content(event) } else { ContentUnavailableView("Message not found", systemImage: "questionmark") }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { speaker.stop(); dismiss() } }
        }
    }

    @ViewBuilder
    private func content(_ event: MessageEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(event)
                messageBubble(event)

                if event.stage == .checking {
                    Card {
                        HStack(spacing: 12) {
                            ProgressView().tint(Theme.blue)
                            Text("Taking a closer look…").font(.headline)
                        }
                    }
                } else if event.rules.decision == .analyze || event.level == .urgent {
                    explanation(event)
                } else {
                    Card {
                        Label(event.rules.decision == .ignored ? (event.rules.ignoreReason ?? "Not a message") : "No warning signs found",
                              systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(Theme.teal)
                        Text("Stead checked this on your phone. It wasn't sent anywhere.")
                            .foregroundStyle(Theme.muted)
                    }
                }

                if event.isWarning { actions(event) }
            }
            .padding(20)
        }
    }

    // MARK: Pieces

    private func header(_ event: MessageEvent) -> some View {
        HStack(alignment: .center, spacing: 16) {
            KittenView(mood: event.stage == .checking ? .looking : event.level.kittenMood, size: 78, veilColor: event.level.color)
            VStack(alignment: .leading, spacing: 8) {
                if event.stage == .done { LevelPill(level: event.level, large: true) }
                Text(event.level == .urgent && event.thread.codeAfterWarning
                     ? "A code arrived right after a suspicious message"
                     : (event.assessment?.headline ?? (event.isWarning ? "Warning signs found" : "Looks normal")))
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func messageBubble(_ event: MessageEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: event.appSymbol)
                Text("\(event.appLabel) · \(event.senderLabel)").lineLimit(1)
                Spacer()
                Text(event.receivedAt, style: .time)
            }
            .font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
            Text(event.body)
                .font(.body).foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Links in this message are not clickable here.").font(.caption2).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private func explanation(_ event: MessageEvent) -> some View {
        let a = event.assessment

        if a?.isPreliminary == true {
            Label("Preliminary: quick on-phone check. Verify independently.", systemImage: "info.circle")
                .font(.subheadline).foregroundStyle(Theme.amber)
        }

        Card {
            HStack {
                Text("Why Stead is worried").font(.headline)
                Spacer()
                Button { speaker.toggle(readAloudText(event)) } label: {
                    Label(speaker.isSpeaking ? "Stop" : "Read aloud", systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if event.thread.codeAfterWarning {
                Text("A security code arrived minutes after a suspicious message\(event.thread.relatedSender.map { " from \($0)" } ?? ""). Scammers often ask for this code. Never share it.")
                    .font(.body)
            } else if let a {
                Text(a.explanationForUser).font(.body)
            }
            if !event.rules.signals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(event.rules.signals) { s in
                        Label(s.label, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Theme.text)
                            .symbolRenderingMode(.palette).foregroundStyle(event.level.color, Theme.text)
                    }
                }
                .padding(.top, 4)
            }
            if event.thread.flaggedCount >= 2 {
                Label("\(event.senderLabel) sent \(event.thread.flaggedCount) suspicious messages in 30 minutes.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline).foregroundStyle(Theme.amber)
            }
        }

        if let a, !a.uncertainties.isEmpty {
            Card {
                Text("What Stead can't confirm").font(.headline)
                ForEach(a.uncertainties, id: \.self) { u in
                    Label(u, systemImage: "questionmark.circle").font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
        }

        if let step = a?.recommendedVerification ?? (event.thread.codeAfterWarning ? "Call your family on a number you know." : nil) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Safe next step", systemImage: "checkmark.shield.fill").font(.headline).foregroundStyle(Theme.teal)
                Text(step).font(.title3.weight(.medium)).foregroundStyle(Theme.text)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.teal.opacity(0.4)))
        }
    }

    @ViewBuilder
    private func actions(_ event: MessageEvent) -> some View {
        VStack(spacing: 12) {
            switch event.familyStatus {
            case .none:
                Button { FamilyBridge.share(event.id) } label: {
                    Label("Ask family to check", systemImage: "person.2.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            default:
                Card {
                    FamilyStatusTag(status: event.familyStatus).font(.headline)
                    Text(event.familyNote ?? familyDetail(event.familyStatus)).foregroundStyle(Theme.muted)
                }
            }
            if !event.dismissedByUser {
                Button {
                    store.update(event.id) { $0.dismissedByUser = true }
                    dismiss()
                } label: {
                    Text("I know this sender, it's fine").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 6)
    }

    private func familyDetail(_ status: MessageEvent.FamilyStatus) -> String {
        switch status {
        case .shared: "Your family can see a short summary and will check it. Wait before you reply."
        case .checking: "Someone in your family is looking into it now."
        case .resolved: "Your family checked this message."
        case .none: ""
        }
    }

    private func readAloudText(_ event: MessageEvent) -> String {
        var parts = [event.level.title + "."]
        if event.thread.codeAfterWarning {
            parts.append("A security code arrived right after a suspicious message. Never share this code. Call your family on a number you know.")
        }
        if let a = event.assessment {
            parts.append(a.explanationForUser)
            parts.append(a.recommendedVerification)
        }
        return parts.joined(separator: " ")
    }
}
