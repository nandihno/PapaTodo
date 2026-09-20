import SwiftUI
import UIKit
import UserNotifications

/// Carries what the system tells the app about push notifications to the model that acts on it.
///
/// The system can deliver a device token or a notification tap before the SwiftUI app has finished
/// starting (a cold launch from a tap), so anything that arrives before a handler is attached is kept
/// and delivered the moment one is.
@MainActor
final class PushBridge {
    static let shared = PushBridge()

    init() {}

    var onDeviceToken: ((Data) -> Void)? {
        didSet {
            if let token = pendingToken, let handler = onDeviceToken { pendingToken = nil; handler(token) }
        }
    }
    var onRegistrationFailure: (() -> Void)?
    var onOpenChore: ((UUID) -> Void)? {
        didSet {
            if let id = pendingChore, let handler = onOpenChore { pendingChore = nil; handler(id) }
        }
    }
    /// A notification arrived while the app was open.
    var onForegroundNotification: (() -> Void)?

    private var pendingToken: Data?
    private var pendingChore: UUID?

    func deviceToken(_ data: Data) {
        if let onDeviceToken { onDeviceToken(data) } else { pendingToken = data }
    }

    func registrationFailed() {
        onRegistrationFailure?()
    }

    func openChore(_ id: UUID) {
        if let onOpenChore { onOpenChore(id) } else { pendingChore = id }
    }

    func foregroundNotification() {
        onForegroundNotification?()
    }
}

/// Receives the system's remote-notification callbacks and notification taps.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushBridge.shared.deviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushBridge.shared.registrationFailed()
    }

    /// Show notifications that arrive while the app is open (specification.md section 10.3).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { PushBridge.shared.foregroundNotification() }
        return [.banner, .list, .sound]
    }

    /// The user tapped a notification: open the chore it is about.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let id = PushPayload.choreID(from: response.notification.request.content.userInfo) else { return }
        await MainActor.run { PushBridge.shared.openChore(id) }
    }
}
