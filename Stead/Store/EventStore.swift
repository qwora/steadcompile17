import Foundation
import SwiftUI

/// One incoming message and everything Stead decided about it. Stays on the phone.
struct MessageEvent: Codable, Identifiable, Hashable {
    enum Source: String, Codable { case shortcut, paste, sample }
    enum Stage: String, Codable { case done, checking }
    enum FamilyStatus: String, Codable { case none, shared, checking, resolved }
    /// "Ask for their family code" state, for messages that claim to be family and ask for something.
    enum FamilyCheck: String, Codable { case needed, verified, failed }

    var id = UUID()
    var receivedAt: Date
    var app: String
    var sender: String
    var subtitle: String
    var body: String
    var source: Source
    var rules: RuleResult
    var thread: ThreadInfo
    var assessment: Assessment?
    var level: Level
    var stage: Stage
    var familyStatus: FamilyStatus = .none
    var familyNote: String?
    var dismissedByUser = false
    var familyMemberID: UUID?
    var familyCheck: FamilyCheck?
    /// The shared case on the server, once this message was sent to the family.
    var caseID: UUID?

    var appLabel: String { app.isEmpty ? "Unknown app" : app }
    var senderLabel: String { sender.isEmpty ? "Unknown sender" : sender }
    var isWarning: Bool { level >= .worthALook }

    var appSymbol: String {
        let a = app.lowercased()
        if a.contains("whatsapp") { return "phone.bubble.fill" }
        if a.contains("message") { return "message.fill" }
        if a.contains("kakao") { return "bubble.left.fill" }
        if a.contains("mail") { return "envelope.fill" }
        return "app.badge.fill"
    }
}

/// Local history of checked messages, saved as JSON in Application Support.
@MainActor
final class EventStore: ObservableObject {
    static let shared = EventStore()

    @Published private(set) var events: [MessageEvent] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "events.json")
    }()

    private init() { reload() }

    /// Re-reads the file: the Shortcuts intent may have written while the UI was in the background.
    func reload() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([MessageEvent].self, from: data) { events = loaded }
    }

    func upsert(_ event: MessageEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) { events[i] = event } else { events.insert(event, at: 0) }
        events.sort { $0.receivedAt > $1.receivedAt }
        if events.count > 500 { events = Array(events.prefix(500)) }
        save()
    }

    func event(id: UUID) -> MessageEvent? { events.first { $0.id == id } }

    func update(_ id: UUID, _ change: (inout MessageEvent) -> Void) {
        guard var e = event(id: id) else { return }
        change(&e)
        upsert(e)
    }

    func clear() { events = []; save() }

    func isDuplicate(app: String, sender: String, body: String, at date: Date) -> Bool {
        events.contains { $0.app == app && $0.sender == sender && $0.body == body && abs($0.receivedAt.timeIntervalSince(date)) < 60 }
    }

    // MARK: Stats for Home

    var today: [MessageEvent] { events.filter { Calendar.current.isDateInToday($0.receivedAt) && $0.rules.decision != .ignored } }
    var openWarnings: [MessageEvent] { events.filter { $0.isWarning && !$0.dismissedByUser && $0.familyStatus != .resolved } }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) { try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
}
