import Foundation
import NaturalLanguage

/// Sends one flagged message to the backend `analyze` function. Never called for normal messages.
enum AnalyzeClient {
    enum Failure: Error { case notConfigured, badResponse, invalidAssessment }

    struct Request: Encodable {
        let app: String
        let sender_kind: String
        let text: String
        let rule_signals: [String]
        let thread_count: Int
        let locale: String
    }

    static func analyze(event: MessageEvent) async throws -> Assessment {
        guard Config.isBackendConfigured else { throw Failure.notConfigured }

        let body = Request(
            app: event.app,
            sender_kind: RulesEngine.senderKind(event.sender),
            text: String(event.body.prefix(4000)),
            rule_signals: event.rules.signals.map(\.id),
            thread_count: event.thread.flaggedCount,
            locale: locale(for: event.body))

        var request = URLRequest(url: Config.analyzeURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let token = await SupabaseService.accessToken() ?? Config.supabaseAnonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.badResponse }
        let assessment = try JSONDecoder().decode(Assessment.self, from: data)
        guard assessment.isValid else { throw Failure.invalidAssessment }
        return assessment
    }

    /// The language Stead should answer in: Korean, Malay or English.
    static func locale(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.korean, .malay, .english, .indonesian]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .korean: return "ko"
        case .malay, .indonesian: return "ms"
        default: return "en"
        }
    }
}
