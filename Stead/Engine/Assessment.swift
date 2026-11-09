import SwiftUI

/// The AI's structured answer (shape agreed with the backend in docs/BACKEND_TASKS.md).
struct Assessment: Codable, Hashable {
    var category: String
    var concernLevel: String
    var asksFor: [String]
    var claimedIdentity: String?
    var requestedAction: String?
    var scamStage: String
    var explanationForUser: String
    var summaryForGuardian: String
    var recommendedVerification: String
    var uncertainties: [String]
    /// True when this came from the on-device fallback, not the AI.
    var isPreliminary: Bool = false

    enum CodingKeys: String, CodingKey {
        case category, uncertainties
        case concernLevel = "concern_level"
        case asksFor = "asks_for"
        case claimedIdentity = "claimed_identity"
        case requestedAction = "requested_action"
        case scamStage = "scam_stage"
        case explanationForUser = "explanation_for_user"
        case summaryForGuardian = "summary_for_guardian"
        case recommendedVerification = "recommended_verification"
        case isPreliminary = "is_preliminary"
    }

    init(category: String, concernLevel: String, asksFor: [String], claimedIdentity: String?, requestedAction: String?,
         scamStage: String, explanationForUser: String, summaryForGuardian: String, recommendedVerification: String,
         uncertainties: [String], isPreliminary: Bool) {
        self.category = category; self.concernLevel = concernLevel; self.asksFor = asksFor
        self.claimedIdentity = claimedIdentity; self.requestedAction = requestedAction; self.scamStage = scamStage
        self.explanationForUser = explanationForUser; self.summaryForGuardian = summaryForGuardian
        self.recommendedVerification = recommendedVerification; self.uncertainties = uncertainties
        self.isPreliminary = isPreliminary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = try c.decode(String.self, forKey: .category)
        concernLevel = try c.decode(String.self, forKey: .concernLevel)
        asksFor = try c.decodeIfPresent([String].self, forKey: .asksFor) ?? []
        claimedIdentity = try c.decodeIfPresent(String.self, forKey: .claimedIdentity)
        requestedAction = try c.decodeIfPresent(String.self, forKey: .requestedAction)
        scamStage = try c.decodeIfPresent(String.self, forKey: .scamStage) ?? "none"
        explanationForUser = try c.decode(String.self, forKey: .explanationForUser)
        summaryForGuardian = try c.decode(String.self, forKey: .summaryForGuardian)
        recommendedVerification = try c.decode(String.self, forKey: .recommendedVerification)
        uncertainties = try c.decodeIfPresent([String].self, forKey: .uncertainties) ?? []
        isPreliminary = try c.decodeIfPresent(Bool.self, forKey: .isPreliminary) ?? false
    }

    static let validCategories: Set<String> = ["government_impersonation", "bank_impersonation", "delivery_scam", "family_impersonation",
                                               "investment_scam", "account_takeover", "romance", "job_scam", "other", "not_a_scam"]
    static let validLevels: Set<String> = ["be_careful", "worth_a_look", "looks_normal"]

    /// Re-checks what the server sent. Anything off → treat as a failed AI call.
    var isValid: Bool {
        Self.validCategories.contains(category) && Self.validLevels.contains(concernLevel)
            && !explanationForUser.isEmpty && explanationForUser.count <= 400
            && summaryForGuardian.count <= 400
    }

    var asksForSomethingRisky: Bool {
        !Set(asksFor).isDisjoint(with: ["money", "code", "install", "link", "personal_info"])
    }

    /// Short, human headline for the category ("Possible fake fine").
    var headline: String {
        switch category {
        case "government_impersonation": "Possible fake government notice"
        case "bank_impersonation": "Possible fake bank message"
        case "delivery_scam": "Possible fake delivery notice"
        case "family_impersonation": "Someone may be pretending to be family"
        case "investment_scam": "Possible investment scam"
        case "account_takeover": "This account may be hacked"
        case "romance": "Possible romance scam"
        case "job_scam": "Possible job scam"
        case "not_a_scam": "Looks like a normal message"
        default: "Something here looks unusual"
        }
    }
}

/// How worried Stead is. Wording is deliberately calm: never "safe", never a percentage.
enum Level: Int, Codable, Comparable {
    case normal = 0, worthALook = 1, beCareful = 2, urgent = 3

    static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .normal: "Looks normal"
        case .worthALook: "Worth a look"
        case .beCareful: "Be careful"
        case .urgent: "Stop and talk to family"
        }
    }

    var color: Color {
        switch self {
        case .normal: Theme.teal
        case .worthALook: Theme.blue
        case .beCareful: Theme.amber
        case .urgent: Theme.red
        }
    }

    var symbol: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .worthALook: "eye.fill"
        case .beCareful: "exclamationmark.triangle.fill"
        case .urgent: "hand.raised.fill"
        }
    }

    var kittenMood: KittenView.Mood {
        switch self {
        case .normal: .watching
        case .worthALook: .looking
        case .beCareful, .urgent: .covering
        }
    }
}
