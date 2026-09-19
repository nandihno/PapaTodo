import Auth
import Foundation
import Helpers
import PostgREST

/// Maps SDK and transport errors to `DataServiceError`. The raw error is never
/// shown to the user or logged with its payload (specification.md 11.2, 11.3).
nonisolated enum SupabaseErrorMapper {
    static func map(_ error: any Error) -> DataServiceError {
        if let known = error as? DataServiceError {
            return known
        }
        if error is CancellationError {
            return .server
        }
        if let urlError = error as? URLError {
            return isConnectivity(urlError) ? .offline : .server
        }
        if let authError = error as? AuthError {
            return map(authError)
        }
        if let postgrestError = error as? PostgrestError {
            return isJWTProblem(code: postgrestError.code, message: postgrestError.message) ? .sessionExpired : .server
        }
        if let httpError = error as? HTTPError {
            return httpError.response.statusCode == 401 ? .sessionExpired : .server
        }
        return .server
    }

    private static func map(_ error: AuthError) -> DataServiceError {
        switch error {
        case .sessionMissing:
            return .sessionExpired
        case .api(_, let code, _, let response):
            switch code {
            case .invalidCredentials:
                return .invalidCredentials
            case .refreshTokenNotFound, .refreshTokenAlreadyUsed, .sessionNotFound,
                 .sessionExpired, .badJWT, .invalidJWT:
                return .sessionExpired
            default:
                return response.statusCode == 401 ? .sessionExpired : .server
            }
        case .jwtVerificationFailed:
            return .sessionExpired
        default:
            return .server
        }
    }

    private static func isConnectivity(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
            true
        default:
            false
        }
    }

    private static func isJWTProblem(code: String?, message: String) -> Bool {
        if code == "PGRST301" || code == "PGRST303" { return true }
        return message.localizedCaseInsensitiveContains("jwt")
    }
}
