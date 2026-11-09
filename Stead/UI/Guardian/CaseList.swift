import SwiftUI

/// Live cases from everyone else in my family circles (Realtime + push), newest first.
struct CaseList: View {
    var onlyOpen = false
    @StateObject private var circle = CircleService.shared

    private var open: [CaseRow] { circle.othersCases.filter { $0.status != "resolved" } }
    private var recent: [CaseRow] { onlyOpen ? [] : Array(circle.othersCases.filter { $0.status == "resolved" }.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if open.isEmpty && !onlyOpen {
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
    private var me: UUID? { circle.myMemberID(in: item.circle_id) }
    private var asksMe: Bool {
        item.kind == "verify_identity" && item.verify_answer == nil && item.status != "resolved"
            && (item.verify_target_member_id == nil || item.verify_target_member_id == me)
    }

    private var resolved: Bool { item.status == "resolved" }

    var body: some View {
        Card {
            HStack {
                Label(level.title, systemImage: level.symbol).font(.headline).foregroundStyle(resolved ? Theme.muted : level.color)
                Spacer()
                Text(item.created_at, style: .relative).font(.caption).foregroundStyle(Theme.muted)
            }
            Text(asksMe
                 ? (item.verify_target_member_id == me ? "Is this you messaging \(person)?" : "Someone says they're family. You?")
                 : "\(person) got a suspicious message")
                .font(.title3.bold())
            if !resolved {
                if let ask = item.requested_action {
                    Label(ask.prefix(1).uppercased() + ask.dropFirst(), systemImage: "hand.raised.fill")
                        .font(.headline).foregroundStyle(level.color).lineLimit(2)
                }
                Text(item.summary_for_guardian).foregroundStyle(Theme.muted).lineLimit(2)
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
