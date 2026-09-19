import Foundation
import Supabase

/// Builds the one `SupabaseClient` the app shares. Only the publishable/anon key
/// is used; row access is enforced by RLS on the signed-in user's JWT
/// (specification.md section 8). The SDK persists the session in the Keychain.
nonisolated enum SupabaseClientFactory {
    static func make(configuration: AppConfiguration) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.supabaseAnonKey
        )
    }
}
