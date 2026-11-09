import Foundation
import Supabase

/// Thin wrapper around the Supabase client. Phase 3 adds circles and cases here.
enum SupabaseService {
    static let client: SupabaseClient? = {
        guard Config.isBackendConfigured else { return nil }
        return SupabaseClient(supabaseURL: Config.supabaseURL, supabaseKey: Config.supabaseAnonKey)
    }()

    /// Signs in anonymously if needed and returns the session token for the `analyze` call.
    static func accessToken() async -> String? {
        guard let client else { return nil }
        if let session = try? await client.auth.session { return session.accessToken }
        return try? await client.auth.signInAnonymously().accessToken
    }
}
