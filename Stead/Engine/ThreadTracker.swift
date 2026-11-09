import Foundation

/// Looks across recent messages, not just one, to spot someone being drawn into a scam.
struct ThreadInfo: Codable, Hashable {
    /// Sum of rule scores from this sender's flagged messages in the last 30 minutes (including this one).
    var senderScore: Int = 0
    /// How many flagged messages this sender sent in the last 30 minutes (including this one).
    var flaggedCount: Int = 0
    /// A one-time code arrived within 15 minutes of a "Be careful" message.
    var codeAfterWarning: Bool = false
    /// The sender of that earlier warning, for the explanation.
    var relatedSender: String?
}

enum ThreadTracker {
    static let senderWindow: TimeInterval = 30 * 60
    static let codeWindow: TimeInterval = 15 * 60
    static let urgentSenderScore = 8

    static func info(for sender: String, app: String, rules: RuleResult, at date: Date, history: [MessageEvent]) -> ThreadInfo {
        var info = ThreadInfo()
        let key = senderKey(sender, app)

        if rules.decision == .analyze {
            let recent = history.filter {
                senderKey($0.sender, $0.app) == key && $0.rules.decision == .analyze
                    && date.timeIntervalSince($0.receivedAt) <= senderWindow && $0.receivedAt <= date
            }
            info.flaggedCount = recent.count + 1
            info.senderScore = recent.reduce(rules.score) { $0 + $1.rules.score }
        }

        if rules.isOneTimeCode,
           let warning = history.first(where: { $0.level >= .beCareful && date.timeIntervalSince($0.receivedAt) <= codeWindow && $0.receivedAt <= date }) {
            info.codeAfterWarning = true
            info.relatedSender = warning.sender
        }
        return info
    }

    private static func senderKey(_ sender: String, _ app: String) -> String {
        app.lowercased() + "|" + TextCleaner.clean(sender).lowercased()
    }
}
