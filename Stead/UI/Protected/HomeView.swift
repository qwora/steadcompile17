import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var router: Router
    @AppStorage("displayName") private var displayName = ""
    @State private var showCheck = false
    @State private var showGuide = false

    private var warnings: [MessageEvent] { store.openWarnings }
    private var topLevel: Level { warnings.map(\.level).max() ?? .normal }
    private var isChecking: Bool { store.events.contains { $0.stage == .checking } }
    private var hasAutomation: Bool { store.events.contains { $0.source == .shortcut } }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                hero
                stats
                if !hasAutomation { setupCard }
                if !warnings.isEmpty {
                    SectionTitle(text: "Needs a look")
                    ForEach(warnings.prefix(3)) { event in
                        Button { router.openEvent = event.id } label: {
                            Card(padding: 14) { EventRow(event: event) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { showCheck = true } label: {
                    Label("Check a message", systemImage: "text.viewfinder")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCheck) { NavigationStack { CheckSheet() } }
        .sheet(isPresented: $showGuide) { NavigationStack { SetupGuideView() } }
        .refreshable { store.reload() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.subheadline).foregroundStyle(Theme.muted)
                Text(displayName.isEmpty ? "Welcome" : displayName).font(.largeTitle.bold())
            }
            Spacer()
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            KittenView(mood: isChecking ? .looking : topLevel.kittenMood, size: 132, veilColor: topLevel.color)
            Text(heroTitle).font(.title.bold()).multilineTextAlignment(.center)
            Text(heroDetail).font(.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(.vertical, 26).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [(topLevel == .normal ? Theme.teal : topLevel.color).opacity(0.16), Theme.surface],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.line))
        .animation(.easeInOut, value: topLevel)
    }

    private var stats: some View {
        HStack(spacing: 12) {
            Stat(value: store.today.count, label: "Checked today", color: Theme.teal)
            Stat(value: store.today.filter(\.isWarning).count, label: "Warnings", color: Theme.amber)
            Stat(value: store.events.filter { $0.familyStatus != .none }.count, label: "Shared", color: Theme.blue)
        }
    }

    private var setupCard: some View {
        Button { showGuide = true } label: {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "bolt.badge.automatic.fill").font(.title).foregroundStyle(Theme.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Turn on automatic checks").font(.headline).foregroundStyle(Theme.text)
                        Text("A 2-minute setup so Stead checks SMS and WhatsApp by itself.")
                            .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var heroTitle: String {
        if isChecking { return "Taking a closer look…" }
        switch topLevel {
        case .normal: return "All quiet"
        case .worthALook: return warnings.count == 1 ? "One message is worth a look" : "\(warnings.count) messages are worth a look"
        case .beCareful: return "Be careful with a message"
        case .urgent: return "Stop. Talk to family first"
        }
    }

    private var heroDetail: String {
        if isChecking { return "Stead is checking a message with warning signs." }
        switch topLevel {
        case .normal: return "Stead is watching your messages. Nothing needs your attention."
        case .worthALook: return "Tap below to see what Stead noticed."
        case .beCareful: return "Don't tap links or send money until you've checked."
        case .urgent: return "Don't share codes or send money. Call your family now."
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

private struct Stat: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title.bold()).foregroundStyle(color).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }
}
