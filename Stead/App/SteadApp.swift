import SwiftUI

@main
struct SteadApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.teal)
        }
    }
}
