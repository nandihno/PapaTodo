import Foundation
import Observation

/// Notification permission and APNs device registration.
///
/// The system hands the app a device token whenever it (re)registers, which can be before anyone is
/// signed in. The token is kept, and filed under the user with the backend only while signed in. It
/// is registered again on each sign-in (tokens can change and the call is idempotent) and removed on
/// sign-out on a best-effort basis: sign-out always completes even if the server call fails.
@Observable
@MainActor
final class PushRegistrationModel {
    enum Registration: Equatable {
        case notRegistered
        case registering
        case registered
        case failed(String)
    }

    private(set) var authorization: NotificationAuthorization = .notDetermined
    private(set) var registration: Registration = .notRegistered
    private(set) var isRequestingPermission = false
    private(set) var deviceToken: String?
    private(set) var isPromptDismissed: Bool

    private let permission: any NotificationPermissionProviding
    private let registry: any NotificationDeviceRegistering
    private let requestRemoteRegistration: @MainActor () -> Void
    private let defaults: UserDefaults
    private var isSignedIn = false
    private var registeredToken: String?

    static let promptDismissedKey = "notificationPromptDismissed"

    init(
        permission: any NotificationPermissionProviding,
        registry: any NotificationDeviceRegistering,
        requestRemoteRegistration: @escaping @MainActor () -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.permission = permission
        self.registry = registry
        self.requestRemoteRegistration = requestRemoteRegistration
        self.defaults = defaults
        self.isPromptDismissed = defaults.bool(forKey: Self.promptDismissedKey)
    }

    /// Whether to show the one-time "turn on notifications" prompt on Home.
    var shouldShowHomePrompt: Bool {
        authorization == .notDetermined && !isPromptDismissed
    }

    func refreshAuthorization() async {
        authorization = await permission.authorization()
    }

    /// The user tapped "Turn On Notifications": show the system prompt, and if allowed, register.
    func enableNotifications() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        authorization = await permission.requestAuthorization()
        isRequestingPermission = false
        if authorization == .authorized { requestRemoteRegistration() }
    }

    func dismissPrompt() {
        isPromptDismissed = true
        defaults.set(true, forKey: Self.promptDismissedKey)
    }

    // MARK: system callbacks

    /// Called with the token Apple issued for this device.
    func didReceiveDeviceToken(_ data: Data) {
        let token = DeviceToken.hex(from: data)
        deviceToken = token
        if isSignedIn { Task { await registerCurrentToken() } }
    }

    func didFailToRegisterForRemoteNotifications() {
        registration = .failed("Couldn't register this device for notifications. Check your connection and try again.")
    }

    // MARK: session lifecycle

    func sessionDidSignIn() async {
        isSignedIn = true
        await refreshAuthorization()
        if authorization == .authorized {
            // Apple asks apps to re-register on every launch; the system replies with the current token.
            requestRemoteRegistration()
            await registerCurrentToken()
        }
    }

    func sessionDidSignOut() {
        isSignedIn = false
        registeredToken = nil
        registration = .notRegistered
    }

    /// Removes this device from the signed-out-to-be user. Best effort: any failure is ignored so
    /// sign-out is never blocked.
    func unregisterBeforeSignOut() async {
        guard let token = registeredToken else { return }
        try? await registry.unregister(deviceToken: token)
        registeredToken = nil
        registration = .notRegistered
    }

    func retry() async {
        if deviceToken == nil { requestRemoteRegistration() }
        await registerCurrentToken()
    }

    // MARK: registration

    func registerCurrentToken() async {
        guard isSignedIn, authorization == .authorized, let token = deviceToken else { return }
        if registeredToken == token, registration == .registered { return }
        guard registration != .registering else { return }
        registration = .registering
        do {
            try await registry.register(deviceToken: token)
            registeredToken = token
            registration = .registered
        } catch {
            registration = .failed(((error as? DataServiceError)?.errorDescription) ?? "Couldn't register this device for notifications.")
        }
    }
}
