//
//  PapaTodosApp.swift
//  PapaTodos
//
//  Created by Fernando De Leon on 18/9/2026.
//

import SwiftUI

@main
struct PapaTodosApp: App {
    @State private var session: AppSession
    @State private var router = AppRouter()

    init() {
        let environment = AppEnvironment.fixture()
        _session = State(initialValue: AppSession(authenticating: environment.authenticating))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(router)
                .task {
                    await session.restore()
                }
        }
    }
}
