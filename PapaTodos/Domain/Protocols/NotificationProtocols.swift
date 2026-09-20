import Foundation

/// Registers this device's APNs token against the signed-in user (the `register_notification_device`
/// and `unregister_notification_device` functions).
nonisolated protocol NotificationDeviceRegistering: Sendable {
    func register(deviceToken: String) async throws
    func unregister(deviceToken: String) async throws
}

/// Asks the backend to notify the other people involved in a chore. Never throws: a notification
/// failure must not make the action that caused it fail (specification.md section 9.8).
nonisolated protocol NotificationDispatching: Sendable {
    func notify(_ event: PushEvent, choreID: UUID) async
}

/// The system notification permission.
nonisolated protocol NotificationPermissionProviding: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Shows the system permission prompt (only when the status is not determined).
    func requestAuthorization() async -> NotificationAuthorization
}
