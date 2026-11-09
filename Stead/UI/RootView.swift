import SwiftUI

/// Who is using this phone. Chosen once during onboarding.
enum AppMode: String { case protected, guardian }

struct RootView: View {
    @AppStorage("mode") private var modeRaw = ""
    @EnvironmentObject private var router: Router

    var body: some View {
        Group {
            switch AppMode(rawValue: modeRaw) {
            // Everyone is protected. Looking out for family is an extra section, not a different app.
            case .protected, .guardian: ProtectedTabs()
            case nil: OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: modeRaw)
    }
}

struct ProtectedTabs: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var store: EventStore

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Router.Tab.home)
            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle.fill") }
                .tag(Router.Tab.activity)
                .badge(store.openWarnings.count)
            NavigationStack { FamilyView() }
                .tabItem { Label("Family", systemImage: "person.2.fill") }
                .tag(Router.Tab.family)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Router.Tab.settings)
        }
        .sheet(item: Binding(get: { router.openEvent.map(EventRef.init) }, set: { router.openEvent = $0?.id })) { ref in
            NavigationStack { MessageCheckView(eventID: ref.id) }
        }
        .fullScreenCover(item: Binding(get: { router.pauseEvent.flatMap(store.event(id:)) }, set: { if $0 == nil { router.pauseEvent = nil } })) { e in
            PauseView(event: e) { router.finishPause(e.id) }
        }
        #if DEBUG
        .task { await DebugSeed.runIfRequested() }
        #endif
    }
}

#if DEBUG
/// Debug-only: launch with `-seedSamples YES` to run every example, `-openSample N` to open one result.
@MainActor
enum DebugSeed {
    static func runIfRequested() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "seedSamples") else { return }
        EventStore.shared.clear()
        // A paired demo family member, so the family-code check can be tried on one phone.
        FamilyStore.shared.resetForDemo()
        let payload = FamilyStore.shared.addMember(name: "Daniel", color: .blue, contactNames: ["Daniel"], phones: [],
                                                   protectedName: "Mum")
        FamilyStore.shared.markPaired(payload.id)
        print("DEMO_CODE_SECRET", payload.encoded)
        var opened: UUID?
        let target = defaults.object(forKey: "openSample") as? Int
        for (i, s) in Samples.all.enumerated() {
            let e = await Pipeline.process(app: s.app, sender: s.sender, subtitle: "", body: s.body,
                                           date: .now.addingTimeInterval(Double(i)), source: .sample)
            if i == target { opened = e.id }
        }
        if let opened { Router.shared.openEvent = opened }
    }
}
#endif

struct EventRef: Identifiable { let id: UUID }

#Preview {
    RootView().environmentObject(EventStore.shared).environmentObject(Router.shared)
}
