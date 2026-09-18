import Foundation
import Testing
@testable import PapaTodos

@MainActor
struct AppRouterTests {
    @Test func pendingRouteIsRetainedUntilConsumed() {
        let router = AppRouter()
        let choreID = UUID()

        #expect(router.pendingChoreRoute == nil)

        router.routeToChore(choreID)
        #expect(router.pendingChoreRoute == choreID)

        let consumed = router.consumePendingRoute()
        #expect(consumed == choreID)
        #expect(router.pendingChoreRoute == nil)
    }

    @Test func consumingWithNoPendingRouteReturnsNil() {
        let router = AppRouter()
        #expect(router.consumePendingRoute() == nil)
    }
}
