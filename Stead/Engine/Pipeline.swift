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

        var event = MessageEvent(
            receivedAt: date, app: app, sender: sender, subtitle: subtitle, body: body, source: source,
            rules: rules, thread: thread, assessment: nil,
            level: Policy.level(rules: rules, assessment: nil, thread: thread),
            stage: rules.decision == .analyze ? .checking : .done)
        store.upsert(event)

        switch rules.decision {
        case .ignored:
            return event
        case .skip:
            if event.level == .urgent {
                Notifier.result(event)
                FamilyBridge.escalate(event)
            } else if Settings.showEveryCheck {
                Notifier.quiet(event)
            }
            return event
        case .analyze:
            Notifier.checking(event)
        }

        let assessment: Assessment
        do {
            assessment = try await AnalyzeClient.analyze(event: event)
        } catch {
            assessment = LocalAssessor.assess(rules)
        }

        event.assessment = assessment
        event.level = Policy.level(rules: rules, assessment: assessment, thread: thread)
        event.stage = .done
        store.upsert(event)

        Notifier.result(event)
        FamilyBridge.escalate(event)
        return store.event(id: event.id) ?? event
    }
}

/// User preferences shared between the app and the background intent.
enum Settings {
    static var showEveryCheck: Bool {
        get { UserDefaults.standard.bool(forKey: "showEveryCheck") }
        set { UserDefaults.standard.set(newValue, forKey: "showEveryCheck") }
    }
    static var autoShareSerious: Bool {
        get { UserDefaults.standard.object(forKey: "autoShareSerious") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoShareSerious") }
    }
}

/// Hands serious cases to the family circle. Phase 3 connects this to Supabase.
@MainActor
enum FamilyBridge {
    static func escalate(_ event: MessageEvent) {
        guard event.level >= .beCareful, Settings.autoShareSerious, event.familyStatus == .none else { return }
        share(event.id)
    }

    /// Marks the case as shared. The Supabase write is added in Phase 3.
    static func share(_ id: UUID) {
        EventStore.shared.update(id) { $0.familyStatus = .shared }
    }
}
