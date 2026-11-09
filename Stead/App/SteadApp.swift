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

    func open(_ id: UUID) {
        EventStore.shared.reload()
        tab = .home
        openEvent = id
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
