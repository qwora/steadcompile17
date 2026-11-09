import SwiftUI

/// Phase 0 shell: proves the app, theme and kitten run on the phone.
/// Mode picker, Home and Guardian screens replace this in later phases.
struct RootView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                KittenView(mood: .watching, size: 150)
                Text("Stead")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Safer, together.")
                    .font(.title3)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Card {
                    Label(Config.isBackendConfigured ? "Backend connected" : "Backend not set up yet",
                          systemImage: Config.isBackendConfigured ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(Config.isBackendConfigured ? Theme.teal : Theme.muted)
                }
            }
            .padding(24)
        }
    }
}

#Preview { RootView() }
