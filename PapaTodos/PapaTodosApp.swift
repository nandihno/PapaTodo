//
//  PapaTodosApp.swift
//  PapaTodos
//
//  Created by Fernando De Leon on 18/9/2026.
//

import SwiftUI

@main
struct PapaTodosApp: App {
    private let environment: AppEnvironment?
    private let configurationError: String?
    @State private var session: AppSession
    @State private var router = AppRouter()

    init() {
        let resolved = Self.resolveEnvironment()
        environment = resolved.environment
        configurationError = resolved.error
        _session = State(initialValue: AppSession(
            authenticating: resolved.environment?.authenticating ?? FixtureAuthenticating()
        ))
    }

    var body: some Scene {
        WindowGroup {
            if let environment {
                ContentView(environment: environment)
                    .environment(session)
                    .environment(router)
                    .preferredColorScheme(Self.forcedColorScheme)
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

    /// `-UITestDarkMode` forces dark appearance from inside the app, because switching
    /// the simulator's appearance isn't reliable. Otherwise the system setting applies.
    private static var forcedColorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains("-UITestDarkMode") ? .dark : nil
    }

    /// `-UITestFixtures` swaps in deterministic fixtures so UI tests never touch
    /// the live backend. `-UITestFailFirstLoad` makes the first chore fetch fail so
    /// the error and retry states can be exercised.
    private static func resolveEnvironment() -> (environment: AppEnvironment?, error: String?) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestFixtures") {
            return (.fixture(failFirstChoreFetches: arguments.contains("-UITestFailFirstLoad") ? 1 : 0), nil)
        }
        do {
            return (.live(configuration: try AppConfiguration.load()), nil)
        } catch {
            return (nil, String(describing: error))
        }
    }
}
