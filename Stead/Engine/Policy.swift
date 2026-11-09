import Foundation

/// Turns rules + AI + thread context into one level. Deterministic, so it can be explained.
enum Policy {
    static func level(rules: RuleResult, assessment: Assessment?, thread: ThreadInfo) -> Level {
        // A code arriving right after a scam warning is the strongest sign someone is about to pay.
        if thread.codeAfterWarning { return .urgent }
        guard rules.decision == .analyze else { return .normal }

        var level: Level
        if let a = assessment, !a.isPreliminary {
            switch a.concernLevel {
            case "be_careful": level = a.asksForSomethingRisky ? .beCareful : .worthALook
            case "worth_a_look": level = .worthALook
            default: level = .normal
            }
        } else {
            // No AI answer: never say "normal". Strong rule matches still reach "Be careful".
            level = rules.score >= 6 ? .beCareful : .worthALook
        }

        // Floors: strong rule matches never drop to "normal".
        if rules.score >= 6 { level = max(level, .worthALook) }
        // One sender keeps pushing.
        if thread.flaggedCount >= 2 && thread.senderScore >= ThreadTracker.urgentSenderScore && level >= .worthALook {
            level = .urgent
        }
        return level
    }
}

/// On-device stand-in for the AI when the backend is not reachable. Always marked preliminary.
enum LocalAssessor {
    static func assess(_ rules: RuleResult) -> Assessment {
        let ids = Set(rules.signals.map(\.id))
        let category: String
        switch true {
        case ids.contains("newphone"): category = "family_impersonation"
        case ids.contains("investment"): category = "investment_scam"
        case ids.contains("attachment") || ids.contains("computer"): category = "account_takeover"
        case ids.contains("authority") && (ids.contains("abroad") || ids.contains("payment")): category = "government_impersonation"
        case ids.contains("authority"): category = "delivery_scam"
        default: category = "other"
        }
        var asks: [String] = []
        if ids.contains("payment") { asks.append("money") }
        if ids.contains("credentials") { asks.append("code") }
        if ids.contains("link") { asks.append("link") }
        if ids.contains("attachment") { asks.append("install") }

        let reasons = rules.signals.prefix(2).map { $0.label.lowercased() }.joined(separator: ", ")
        return Assessment(
            category: category,
            concernLevel: rules.score >= 6 ? "be_careful" : "worth_a_look",
            asksFor: asks.isEmpty ? ["none"] : asks,
            claimedIdentity: nil,
            requestedAction: nil,
            scamStage: "none",
            explanationForUser: "It \(reasons). Don't tap links or send money.",
            summaryForGuardian: "A message with warning signs (\(reasons)).",
            recommendedVerification: "Call them on a number you already have.",
            uncertainties: ["The full AI check wasn't available."],
            isPreliminary: true)
    }
}
