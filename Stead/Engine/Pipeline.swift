import Foundation

/// The whole check for one message: rules → thread → notify → AI → policy → notify.
@MainActor
enum Pipeline {
    @discardableResult
    static func process(app: String, sender: String, subtitle: String, body: String,
                        date: Date = .now, source: MessageEvent.Source) async -> MessageEvent {
        let store = EventStore.shared
        store.reload()

        if store.isDuplicate(app: app, sender: sender, body: body, at: date),
           let existing = store.events.first(where: { $0.app == app && $0.sender == sender && $0.body == body }) {
            return existing
        }

        let rules = RulesEngine.evaluate(app: app, title: sender, subtitle: subtitle, body: body)
        let thread = ThreadTracker.info(for: sender, app: app, rules: rules, at: date, history: store.events)
        let family = FamilyCheckRule.evaluate(sender: sender, rules: rules)

        var event = MessageEvent(
            receivedAt: date, app: app, sender: sender, subtitle: subtitle, body: body, source: source,
            rules: rules, thread: thread, assessment: nil,
            level: Policy.level(rules: rules, assessment: nil, thread: thread),
            stage: rules.decision == .analyze || family.needed ? .checking : .done)
        event.familyMemberID = family.memberID
        if family.needed {
            event.familyCheck = .needed
            event.level = max(event.level, .beCareful)
        }
        store.upsert(event)

        switch rules.decision {
        case .ignored:
            return event
        case .skip where !family.needed:
            if event.level == .urgent {
                Notifier.result(event)
                await FamilyBridge.escalate(event)
            } else if Settings.showEveryCheck {
                Notifier.quiet(event)
            }
            return event
        default:
            // A family check is urgent on its own: tell her before the AI answers.
            if family.needed { Notifier.result(event) } else if Settings.alertFrom <= .worthALook { Notifier.checking(event) }
        }

        let assessment: Assessment
        do {
            assessment = try await AnalyzeClient.analyze(event: event)
        } catch {
            assessment = LocalAssessor.assess(rules)
        }

        event.assessment = assessment
        event.level = Policy.level(rules: rules.decision == .skip ? rules.forcingAnalyze : rules, assessment: assessment, thread: thread)
        if family.needed { event.level = max(event.level, .beCareful) }
        event.stage = .done
        store.upsert(event)

        if !family.needed {
            if event.level >= Settings.alertFrom { Notifier.result(event) }
            else { Notifier.clear(event) }  // replace the "taking a closer look" notice quietly
        }
        await FamilyBridge.escalate(event)
        return store.event(id: event.id) ?? event
    }
}

/// Messages that come from (or claim to be) family and ask for money, a code, or secrecy.
@MainActor
enum FamilyCheckRule {
    struct Result { var needed = false; var memberID: UUID? }

    static let asks: Set<String> = ["payment", "credentials", "newphone", "nocall"]

    static func evaluate(sender: String, rules: RuleResult) -> Result {
        guard rules.decision != .ignored else { return Result() }
        let ids = Set(rules.signals.map(\.id))
        let members = FamilyStore.shared.members
        // A linked family contact asking for money, a code, or not to call.
        if let m = FamilyStore.shared.member(matching: sender), !ids.isDisjoint(with: asks) {
            return Result(needed: true, memberID: m.id)
        }
        // A stranger claiming a new phone and asking for money: someone may be pretending to be family.
        if !members.isEmpty, ids.contains("newphone"), !ids.isDisjoint(with: ["payment", "credentials", "nocall"]) {
            return Result(needed: true, memberID: nil)
        }
        return Result()
    }
}

extension RuleResult {
    /// Same signals, treated as worth a look (used when a family check forces a closer look).
    var forcingAnalyze: RuleResult { RuleResult(decision: .analyze, score: score, signals: signals, ignoreReason: nil) }
}

/// User preferences shared between the app and the background intent.
enum Settings {
    static var showEveryCheck: Bool {
        get { UserDefaults.standard.bool(forKey: "showEveryCheck") }
        set { UserDefaults.standard.set(newValue, forKey: "showEveryCheck") }
    }
    /// "Warn me when": the lowest level that gets a notification. Family-code checks always notify.
    static var alertFrom: Level {
        get { Level(rawValue: UserDefaults.standard.object(forKey: "alertFrom") as? Int ?? Level.worthALook.rawValue) ?? .worthALook }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "alertFrom") }
    }
    /// "Pause before urgent messages": the full-screen moment to stop and call family. On by default.
    static var pauseOnUrgent: Bool {
        get { UserDefaults.standard.object(forKey: "pauseOnUrgent") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pauseOnUrgent") }
    }
    static var autoShareSerious: Bool {
        get { UserDefaults.standard.object(forKey: "autoShareSerious") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoShareSerious") }
    }
}

/// Hands serious cases to the family circle (Supabase `cases`; the server decides who gets a push).
@MainActor
enum FamilyBridge {
    /// Awaited by the pipeline, so a background Shortcut run doesn't end before the case is written.
    static func escalate(_ event: MessageEvent) async {
        guard event.level >= .beCareful, Settings.autoShareSerious, event.familyStatus == .none else { return }
        EventStore.shared.update(event.id) { $0.familyStatus = .shared }
        if let shared = EventStore.shared.event(id: event.id) { await CircleService.shared.share(shared, requested: false) }
    }

    /// `requested`: she tapped "Ask family" herself, so family is told even at Level 1.
    static func share(_ id: UUID, requested: Bool = true) {
        EventStore.shared.update(id) { $0.familyStatus = .shared }
        guard let event = EventStore.shared.event(id: id) else { return }
        Task { await CircleService.shared.share(event, requested: requested) }
    }
}
