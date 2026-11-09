import Foundation
import UserNotifications

/// Local notifications. Each message gets one notification that is replaced as Stead learns more.
@MainActor
enum Notifier {
    static let warningCategory = "STEAD_WARNING"
    static let eventKey = "eventID"

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let open = UNNotificationAction(identifier: "OPEN", title: "See why", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: warningCategory, actions: [open], intentIdentifiers: [])])
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func checking(_ event: MessageEvent) {
        post(event, title: "Stead · Taking a closer look",
             body: "Wait before you reply.",
             level: .worthALook, sound: false)
    }

    static func result(_ event: MessageEvent) {
        let headline = event.assessment?.headline ?? "Warning signs found"
        let title: String
        let body: String
        if event.familyCheck == .needed {
            let name = event.familyMemberID.flatMap { FamilyStore.shared.member(id: $0)?.name }
            title = "Stead · Check the family code first"
            body = name.map { "\($0) is asking for something. Ask for the family code first." }
                ?? "Someone says they're family. Ask for the family code first."
            post(event, title: title, body: body, level: .urgent, sound: true)
            return
        }
        switch event.level {
        case .normal:
            title = "Stead · Looks normal"
            body = "The message from \(event.senderLabel) looks like an ordinary message."
        case .worthALook:
            title = "Stead · Worth a look"
            body = "\(headline). Tap to see why."
        case .beCareful:
            title = "Stead · Be careful"
            body = "\(headline). Don't tap links or send money."
        case .urgent:
            title = "Stead · Stop and talk to family"
            body = event.thread.codeAfterWarning
                ? "Don't share the code you just got. Call family."
                : "Call your family before you do anything."
        }
        post(event, title: title, body: body, level: event.level, sound: event.level >= .beCareful)
    }

    /// Removes this message's notification (used when the final level is below "Warn me when").
    static func clear(_ event: MessageEvent) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [event.id.uuidString])
    }

    /// Quiet notice for normal messages, only when the user turned on "Show every check".
    static func quiet(_ event: MessageEvent) {
        post(event, title: "Stead · Checked", body: "Message from \(event.senderLabel) looks normal.", level: .normal, sound: false)
    }

    private static func post(_ event: MessageEvent, title: String, body: String, level: Level, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = warningCategory
        content.userInfo = [eventKey: event.id.uuidString]
        content.threadIdentifier = "stead"
        content.interruptionLevel = level >= .beCareful ? .timeSensitive : (level == .normal ? .passive : .active)
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
