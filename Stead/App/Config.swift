import Foundation

/// Public configuration. The Supabase anon key is meant to ship in apps:
/// row-level security decides what it can read. The AI key never lives here.
enum Config {
    static let supabaseURL = URL(string: "https://xdbvowflznhepcfmbrnj.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhkYnZvd2Zsem5oZXBjZm1icm5qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQxNjU1ODYsImV4cCI6MjEwOTc0MTU4Nn0.xhFAc19dkPqzYIfuc6gV5w2gL3evRIKeHOFBqUJH4nM"

    static var analyzeURL: URL { supabaseURL.appending(path: "functions/v1/analyze") }
    static var isBackendConfigured: Bool { !supabaseAnonKey.hasPrefix("YOUR-") }
}
