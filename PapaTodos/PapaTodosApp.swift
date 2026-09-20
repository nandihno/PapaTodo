//
//  PapaTodosApp.swift
//  PapaTodos
//
//  Created by Fernando De Leon on 18/9/2026.
//

import SwiftUI

@main
struct PapaTodosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let environment: AppEnvironment?
    private let configurationError: String?
    @State private var session: AppSession
    @State private var router: AppRouter
    @State private var push: PushRegistrationModel

    init() {
        let resolved = Self.resolveEnvironment()
        environment = resolved.environment
        configurationError = resolved.error

        let sessionModel = AppSession(authenticating: resolved.environment?.authenticating ?? FixtureAuthenticating())
        let routerModel = AppRouter()
        let fallback = AppEnvironment.fixture()
        let services = resolved.environment ?? fallback
        let isFixtureRun = ProcessInfo.processInfo.arguments.contains("-UITestFixtures")
        let pushModel = PushRegistrationModel(
            permission: services.notificationPermission,
            registry: services.deviceRegistry,
            // Fixture runs never talk to Apple's push service.
            requestRemoteRegistration: { if !isFixtureRun { UIApplication.shared.registerForRemoteNotifications() } },
            // Fixture runs get a throwaway store so "Not Now" in one UI test can't leak into the next.
            defaults: isFixtureRun ? (UserDefaults(suiteName: "uitest-\(UUID().uuidString)") ?? .standard) : .standard
        )

        // What the system reports goes to these models. Anything that arrives before this point
        // (a cold launch from a notification tap) was held by the bridge and is delivered now.
        PushBridge.shared.onDeviceToken = { pushModel.didReceiveDeviceToken($0) }
        PushBridge.shared.onRegistrationFailure = { pushModel.didFailToRegisterForRemoteNotifications() }
        PushBridge.shared.onOpenChore = { routerModel.routeToChore($0) }
        // Take this device off the user's push list before their session is cleared.
        sessionModel.beforeSignOut = { await pushModel.unregisterBeforeSignOut() }

        // UI tests: behave as if a notification about this chore was tapped before sign-in.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-UITestNotificationTapChore"), index + 1 < arguments.count,
           let id = UUID(uuidString: arguments[index + 1]) {
            routerModel.routeToChore(id)
        }

        _session = State(initialValue: sessionModel)
        _router = State(initialValue: routerModel)
        _push = State(initialValue: pushModel)
    }

    var body: some Scene {
        WindowGroup {
            if let environment {
                ContentView(environment: environment)
                    .environment(session)
                    .environment(router)
                    .environment(push)
                    .task { await session.restore() }
            } else {
                ContentUnavailableView(
                    "Configuration missing",
                    systemImage: "exclamationmark.triangle",
                    description: Text(configurationError ?? "")
                )
            }
        }
    }

    /// `-UITestFixtures` swaps in deterministic fixtures so UI tests never touch the live backend.
    /// The other `-UITest...` arguments shape those fixtures; see AGENTS.md.
    private static func resolveEnvironment() -> (environment: AppEnvironment?, error: String?) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestFixtures") {
            return (.fixture(
                failFirstChoreFetches: arguments.contains("-UITestFailFirstLoad") ? 1 : 0,
                remoteComment: arguments.contains("-UITestRemoteComment"),
                storageRefusesDeletes: arguments.contains("-UITestStorageRefusesDeletes"),
                notificationStatus: notificationStatus(from: arguments)
            ), nil)
        }
        do {
            return (.live(configuration: try AppConfiguration.load()), nil)
        } catch {
            return (nil, String(describing: error))
        }
    }

    /// Fixture runs default to "already allowed" so the one-time Home prompt doesn't push the list down in
    /// tests that aren't about notifications; the notification tests ask for `notDetermined` explicitly.
    private static func notificationStatus(from arguments: [String]) -> NotificationAuthorization {
        guard let index = arguments.firstIndex(of: "-UITestNotificationStatus"), index + 1 < arguments.count else {
            return .authorized
        }
        switch arguments[index + 1] {
        case "authorized": return .authorized
        case "denied": return .denied
        default: return .notDetermined
        }
    }
}
