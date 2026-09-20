import UserNotifications

/// `UNUserNotificationCenter` behind the app's `NotificationPermissionProviding` protocol.
nonisolated struct SystemNotificationPermission: NotificationPermissionProviding {
    func authorization() async -> NotificationAuthorization {
        Self.map(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorization {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return await authorization()
    }

    static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .denied
        }
    }
}
