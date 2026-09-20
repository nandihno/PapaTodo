import Foundation

/// Records device registrations; never talks to Supabase or Apple.
actor FixtureNotificationDeviceRegistry: NotificationDeviceRegistering {
    private(set) var registered: [String] = []
    private(set) var unregistered: [String] = []
    private var registerFailures: [DataServiceError] = []
    private var unregisterFailures: [DataServiceError] = []
    private var delay: Duration?

    func register(deviceToken: String) async throws {
        if let delay { try? await Task.sleep(for: delay) }
        if !registerFailures.isEmpty { throw registerFailures.removeFirst() }
        registered.append(deviceToken)
    }

    func unregister(deviceToken: String) async throws {
        if let delay { try? await Task.sleep(for: delay) }
        if !unregisterFailures.isEmpty { throw unregisterFailures.removeFirst() }
        unregistered.append(deviceToken)
    }

    func failNextRegister(with error: DataServiceError = .offline) { registerFailures.append(error) }
    func failNextUnregister(with error: DataServiceError = .offline) { unregisterFailures.append(error) }
    /// Makes calls slow, to prove sign-out doesn't wait forever on a hung unregister.
    func setDelay(_ delay: Duration?) { self.delay = delay }
}

/// Records the notifications the app asked for.
actor FixtureNotificationDispatcher: NotificationDispatching {
    struct Sent: Equatable, Sendable {
        let event: PushEvent
        let choreID: UUID
    }

    private(set) var sent: [Sent] = []

    func notify(_ event: PushEvent, choreID: UUID) async {
        sent.append(Sent(event: event, choreID: choreID))
    }
}

/// A permission provider whose answer the test (or a UI-test launch argument) chooses.
actor FixtureNotificationPermission: NotificationPermissionProviding {
    private var current: NotificationAuthorization
    private var answerToRequest: NotificationAuthorization
    private(set) var requestCount = 0

    init(current: NotificationAuthorization = .notDetermined, answerToRequest: NotificationAuthorization = .authorized) {
        self.current = current
        self.answerToRequest = answerToRequest
    }

    func authorization() async -> NotificationAuthorization { current }

    func requestAuthorization() async -> NotificationAuthorization {
        requestCount += 1
        if current == .notDetermined { current = answerToRequest }
        return current
    }

    func setAuthorization(_ value: NotificationAuthorization) { current = value }
}
