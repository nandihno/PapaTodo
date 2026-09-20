import Foundation

/// The notification permission the user has given, independent of `UserNotifications` so it can be
/// faked in tests.
nonisolated enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    /// Allowed, including provisional and ephemeral grants.
    case authorized
}

/// The events the backend's `send-push` function understands (the same names the web app sends).
nonisolated enum PushEvent: String, Sendable, Equatable {
    case choreAssigned = "chore-assigned"
    case choreUpdated = "chore-updated"
    case commentCreated = "comment-created"
    case statusChanged = "status-changed"
}

nonisolated enum DeviceToken {
    /// The lowercase hexadecimal form the `register_notification_device` function requires.
    static func hex(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Short form for diagnostics. The full token is never logged.
    static func redacted(_ token: String) -> String {
        token.count <= 6 ? "…" : "…" + token.suffix(6)
    }
}

nonisolated enum PushPayload {
    /// The chore a notification is about: the `choreId` the backend puts in the payload.
    static func choreID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let raw = userInfo["choreId"] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}
