import AppIntents
import Foundation

/// Called by the Shortcuts automation "When I receive a notification from …".
/// Runs in the background without opening Stead.
struct CheckMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Message"
    static let description = IntentDescription("Stead checks a new message notification for scam warning signs.")
    static let openAppWhenRun = false

    @Parameter(title: "App") var app: String?
    @Parameter(title: "Title") var heading: String?
    @Parameter(title: "Subtitle") var subtitle: String?
    @Parameter(title: "Body") var body: String?
    @Parameter(title: "Date") var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Check message from \(\.$app)") {
            \.$heading
            \.$subtitle
            \.$body
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await Pipeline.process(app: app ?? "", sender: heading ?? "", subtitle: subtitle ?? "",
                               body: body ?? "", date: date ?? .now, source: .shortcut)
        return .result()
    }
}

struct SteadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CheckMessageIntent(),
                    phrases: ["Check a message with \(.applicationName)"],
                    shortTitle: "Check Message",
                    systemImageName: "checkmark.shield")
    }
}
