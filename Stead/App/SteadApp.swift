import SwiftUI
import UserNotifications

@main
struct SteadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = EventStore.shared
    @StateObject private var router = Router.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .tint(Theme.teal)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.reload()
                        router.pauseIfUrgent()
                        Task { await CircleService.shared.refresh() }
                    }
                }
        }
    }
}

/// Which tab is showing and which message (if any) is open, e.g. from a notification tap.
@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    enum Tab: Hashable { case home, activity, family, settings }

    @Published var tab: Tab = .home
    @Published var openEvent: UUID?
    /// An urgent message to pause on before its details open.
    @Published var pauseEvent: UUID?

    func open(_ id: UUID) {
        EventStore.shared.reload()
        tab = .home
        if EventStore.shared.event(id: id)?.needsPause == true { pauseEvent = id } else { openEvent = id }
    }

    /// On opening the app: pause on an urgent message from the last 30 minutes that hasn't been paused on.
    func pauseIfUrgent() {
        guard pauseEvent == nil, let e = EventStore.shared.events.first(where: {
            $0.needsPause && $0.receivedAt > .now.addingTimeInterval(-30 * 60)
        }) else { return }
        openEvent = nil
        pauseEvent = e.id
    }

    func finishPause(_ id: UUID) {
        EventStore.shared.update(id) { $0.pausedAt = .now }
        pauseEvent = nil
        // Let the full-screen cover finish closing; SwiftUI drops a sheet presented mid-dismissal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openEvent = id }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if Config.isBackendConfigured { application.registerForRemoteNotifications() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in CircleService.shared.setPushToken(deviceToken) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { EventStore.shared.reload() }
        if notification.request.content.userInfo["case_id"] != nil {
            await CircleService.shared.refresh()   // a family push: pull the latest case
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Family push from the server: it carries only a case id; details are fetched after opening.
        if let raw = response.notification.request.content.userInfo["case_id"] as? String, let caseID = UUID(uuidString: raw) {
            await MainActor.run { CircleService.shared.openCase(caseID) }
            return
        }
        guard let raw = response.notification.request.content.userInfo[Notifier.eventKey] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { Router.shared.open(id) }
    }
}
