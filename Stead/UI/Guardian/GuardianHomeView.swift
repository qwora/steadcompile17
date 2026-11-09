import SwiftUI

/// Guardian side. Phase 3 replaces the placeholder with the live case list from Supabase.
struct GuardianHomeView: View {
    @AppStorage("displayName") private var displayName = ""
    @AppStorage("mode") private var modeRaw = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    KittenView(color: Theme.blue, mood: .watching, size: 130).padding(.top, 30)
                    Text("Hi \(displayName)").font(.largeTitle.bold())
                    Text("When someone you look out for gets a likely scam, it shows up here and you can tell them \"I'm checking\".")
                        .font(.title3).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    Card {
                        Text("Join a family circle").font(.headline)
                        Text("Ask them for the 6-digit code in their Stead app.").foregroundStyle(Theme.muted)
                        Button("Enter code") {}.buttonStyle(PrimaryButtonStyle(tint: Theme.blue))
                            .disabled(!Config.isBackendConfigured).opacity(Config.isBackendConfigured ? 1 : 0.5)
                        if !Config.isBackendConfigured {
                            Label("Connects once the server is set up.", systemImage: "clock").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .toolbar {
                Menu { Button("Switch who this phone is for") { modeRaw = "" } } label: { Image(systemName: "gearshape.fill") }
            }
        }
    }
}
