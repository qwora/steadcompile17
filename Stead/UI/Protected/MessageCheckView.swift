import SwiftUI

/// The explanation screen: what the message is, why Stead is worried, what it can't know, what to do.
struct MessageCheckView: View {
    let eventID: UUID
    @EnvironmentObject private var store: EventStore
    @StateObject private var speaker = Speaker.shared
    @Environment(\.dismiss) private var dismiss
    @State private var asking = false
    @State private var askFailed = false

    var body: some View {
        Group {
            if let event = store.event(id: eventID) { content(event) } else { ContentUnavailableView("Message not found", systemImage: "questionmark") }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.update(eventID) { if $0.pausedAt == nil { $0.pausedAt = .now } } }
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
                if event.familyCheck != nil { FamilyCodeCheckCard(event: event) }

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
                        Text("Checked on your phone only.")
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
                Text(headline(event))
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
            Text("Links here don't open.").font(.caption2).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private func explanation(_ event: MessageEvent) -> some View {
        let a = event.assessment

        if a?.isPreliminary == true {
            Label("Quick check only. Please double-check.", systemImage: "info.circle")
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
                Text("A code arrived right after a suspicious message. Never share it.")
                    .font(.body)
            } else if let a {
                Text(a.explanationForUser).font(.body)
            }
            if !event.rules.signals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(event.rules.signals.prefix(3)) { s in
                        Label {
                            Text(s.label).foregroundStyle(Theme.text)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(event.level.color)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.top, 4)
            }
            if event.thread.flaggedCount >= 2 {
                Label("\(event.thread.flaggedCount) suspicious messages from this sender", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline).foregroundStyle(Theme.amber)
            }
        }

        if let a, !a.uncertainties.isEmpty {
            Card {
                Text("Stead can't check").font(.headline)
                ForEach(a.uncertainties.prefix(1), id: \.self) { u in
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
                Button {
                    asking = true; askFailed = false
                    Task { askFailed = !(await FamilyBridge.share(event.id)); asking = false }
                } label: {
                    Label(asking ? "Asking family…" : "Ask family to check", systemImage: "person.2.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(asking)
                if askFailed {
                    Text("Couldn't reach your family. Check the internet, or add family in the Family tab.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
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
                    Text("I know them, it's fine").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 6)
    }

    private func headline(_ event: MessageEvent) -> String {
        if event.familyCheck != nil {
            let name = event.familyMemberID.flatMap { FamilyStore.shared.member(id: $0)?.name }
            switch event.familyCheck {
            case .verified: return "Checked: this is really \(name ?? "family")"
            case .failed: return "This may not be \(name ?? "who they say")"
            default: return name.map { "\($0) is asking for something" } ?? "Someone says they're family"
            }
        }
        if event.level == .urgent && event.thread.codeAfterWarning { return "A code arrived right after a suspicious message" }
        return event.assessment?.headline ?? (event.isWarning ? "Warning signs found" : "Looks normal")
    }

    private func familyDetail(_ status: MessageEvent.FamilyStatus) -> String {
        switch status {
        case .shared: "Your family will check. Wait before you reply."
        case .checking: "Your family is checking now."
        case .resolved: "Your family checked it."
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
