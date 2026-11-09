import Foundation

/// Public configuration. The Supabase anon key is meant to ship in apps:
/// row-level security decides what it can read. The AI key never lives here.
enum Config {
    static let supabaseURL = URL(string: "https://YOUR-PROJECT.supabase.co")!
    static let supabaseAnonKey = "YOUR-ANON-KEY"

    static var analyzeURL: URL { supabaseURL.appending(path: "functions/v1/analyze") }
    static var isBackendConfigured: Bool { !supabaseAnonKey.hasPrefix("YOUR-") }
}
