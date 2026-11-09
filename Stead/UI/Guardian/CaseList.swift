import SwiftUI

/// Guardian side: live cases from the people I look out for (Realtime + push), newest first.
struct CaseList: View {
    @StateObject private var circle = CircleService.shared

    private var open: [CaseRow] { circle.cases.filter { $0.status != "resolved" } }
    private var recent: [CaseRow] { Array(circle.cases.filter { $0.status == "resolved" }.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if open.isEmpty {
                Card {
                    Label("All quiet", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.teal)
                    Text("Nothing needs you right now. You'll get a notification if something does.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            ForEach(open) { CaseCard(item: $0, highlighted: $0.id == circle.focusCaseID) }
            if !recent.isEmpty {
                Text("Recently handled").font(.headline).foregroundStyle(Theme.muted).padding(.top, 6)
                ForEach(recent) { CaseCard(item: $0, highlighted: false) }
            }
        }
    }
}

private struct CaseCard: View {
    let item: CaseRow
    let highlighted: Bool
    @StateObject private var circle = CircleService.shared
    @State private var busy = false

    private var level: Level { Level(rawValue: item.level) ?? .beCareful }
    private var person: String { circle.name(of: item.protected_member_id) ?? "Family" }
    private var me: UUID? { circle.memberships.first { $0.circleID == item.circle_id }?.memberID }
    private var asksMe: Bool {
        item.kind == "verify_identity" && item.verify_answer == nil
            && (item.verify_target_member_id == nil || item.verify_target_member_id == me)
    }

    var body: some View {
        Card {
            HStack {
                Label(level.title, systemImage: level.symbol).font(.headline).foregroundStyle(level.color)
                Spacer()
                Text(item.created_at, style: .relative).font(.caption).foregroundStyle(Theme.muted)
            }
            Text(asksMe
                 ? (item.verify_target_member_id == me ? "Someone messaging \(person) says they're you." : "Someone messaging \(person) says they're family. Is it you?")
                 : "\(person) got a message that may be a scam")
                .font(.title3.bold())
            Text(item.summary_for_guardian).foregroundStyle(Theme.text)
            if let how = item.recommended_verification {
                Label(how, systemImage: "checkmark.shield").font(.subheadline).foregroundStyle(Theme.muted)
            }
            if let from = item.sender_label {
                Text([item.app, from].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.muted)
            }
            actions
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .stroke(highlighted ? level.color : .clear, lineWidth: 2))
        .disabled(busy)
    }

    @ViewBuilder
    private var actions: some View {
        if asksMe {
            Button("No, that's not me") { run { await circle.answer(item, itWasMe: false) } }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.red))
            Button("Yes, it's me") { run { await circle.answer(item, itWasMe: true) } }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        } else {
            switch item.status {
            case "open":
                Button("I'm checking") { run { await circle.setStatus(item, "checking") } }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.blue))
            case "checking":
                Text("\(circle.name(of: item.handled_by) ?? "Someone") is checking").font(.subheadline).foregroundStyle(Theme.muted)
                Button("Mark as handled") { run { await circle.setStatus(item, "resolved") } }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.teal))
            default:
                Text(item.verify_answer.map { $0 == "no" ? "Answered: not them" : "Answered: it was them" }
                     ?? item.resolution ?? "Handled").font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task { await work(); busy = false }
    }
}
