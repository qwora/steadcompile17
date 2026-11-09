import SwiftUI

/// Family circle. Phase 3 connects this to Supabase (create circle, invite code, live members).
struct FamilyView: View {
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var router: Router

    private var shared: [MessageEvent] { store.events.filter { $0.familyStatus != .none } }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card {
                    HStack(spacing: -10) {
                        KittenView(color: Theme.teal, mood: .watching, size: 56)
                        KittenView(color: Theme.blue, mood: .happy, size: 56)
                        KittenView(color: Theme.amber, mood: .watching, size: 56)
                    }
                    Text("Your family circle").font(.title2.bold())
                    Text("Invite the people you trust. When Stead sees a likely scam, they get a short heads-up and can tell you \"I'm checking\".")
                        .foregroundStyle(Theme.muted)
                    Button {} label: { Label("Invite family", systemImage: "person.badge.plus") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!Config.isBackendConfigured)
                        .opacity(Config.isBackendConfigured ? 1 : 0.5)
                    if !Config.isBackendConfigured {
                        Label("Family sharing connects once the server is set up.", systemImage: "clock")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                }

                SectionTitle(text: "Shared with family")
                if shared.isEmpty {
                    Text("Nothing shared yet.").foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(shared) { event in
                    Button { router.openEvent = event.id } label: { Card(padding: 14) { EventRow(event: event) } }
                        .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Family")
    }
}
