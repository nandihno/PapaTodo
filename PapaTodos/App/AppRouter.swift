import Foundation
import Observation

/// Observable navigation state. Holds a pending chore route for notification-tap
/// deep linking, per specification.md section 10.3: if auth restoration is still
/// in progress when a notification is tapped, the route is retained here and
/// consumed once sign-in succeeds.
@Observable
@MainActor
final class AppRouter {
    private(set) var pendingChoreRoute: UUID?

    func routeToChore(_ id: UUID) {
        pendingChoreRoute = id
    }

    @discardableResult
    func consumePendingRoute() -> UUID? {
        defer { pendingChoreRoute = nil }
        return pendingChoreRoute
    }
}
