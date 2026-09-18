import Foundation

/// Client-safe configuration loaded from Info.plist (populated by Configuration/Config.xcconfig).
///
/// Values here must never include server-only secrets (service-role key, APNs
/// private key, Web Push VAPID private key). The Supabase key is the
/// publishable/anon key, which is designed for client use — access control
/// comes from RLS, not from keeping this value secret.
struct AppConfiguration: Sendable {
    enum APNsEnvironment: String, Sendable {
        case sandbox
        case production
    }

    let supabaseURL: URL
    let supabaseAnonKey: String
    let bundleIdentifier: String
    let apnsEnvironment: APNsEnvironment

    enum LoadError: Error, CustomStringConvertible {
        case missingKey(String)
        case invalidURL(String)
        case missingBundleIdentifier

        var description: String {
            switch self {
            case .missingKey(let key):
                "Missing or empty Info.plist key \"\(key)\". Copy Configuration/Local.xcconfig.example to Configuration/Local.xcconfig and fill in real values."
            case .invalidURL(let value):
                "Info.plist key \"PBSupabaseURL\" is not a valid URL: \"\(value)\"."
            case .missingBundleIdentifier:
                "Bundle.main.bundleIdentifier is unexpectedly nil."
            }
        }
    }

    static func load(bundle: Bundle = .main) throws -> AppConfiguration {
        guard let urlString = bundle.object(forInfoDictionaryKey: "PBSupabaseURL") as? String,
              !urlString.isEmpty else {
            throw LoadError.missingKey("PBSupabaseURL")
        }
        guard let supabaseURL = URL(string: urlString) else {
            throw LoadError.invalidURL(urlString)
        }
        guard let anonKey = bundle.object(forInfoDictionaryKey: "PBSupabaseAnonKey") as? String,
              !anonKey.isEmpty else {
            throw LoadError.missingKey("PBSupabaseAnonKey")
        }
        guard let bundleIdentifier = bundle.bundleIdentifier else {
            throw LoadError.missingBundleIdentifier
        }

        #if DEBUG
        let apnsEnvironment = APNsEnvironment.sandbox
        #else
        let apnsEnvironment = APNsEnvironment.production
        #endif

        return AppConfiguration(
            supabaseURL: supabaseURL,
            supabaseAnonKey: anonKey,
            bundleIdentifier: bundleIdentifier,
            apnsEnvironment: apnsEnvironment
        )
    }
}
