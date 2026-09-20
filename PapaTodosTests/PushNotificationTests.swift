import Foundation
import Testing
@testable import PapaTodos

struct PushTypesTests {
    @Test func aDeviceTokenBecomesLowercaseHexThatSatisfiesTheDatabaseRule() {
        let token = DeviceToken.hex(from: Data([0x00, 0x0A, 0xFF, 0x10, 0xAB]))
        #expect(token == "000aff10ab")
        // The database requires 32 to 512 lowercase hex characters.
        let full = DeviceToken.hex(from: Data((0..<32).map { UInt8($0 * 8 % 256) }))
        #expect(full.count == 64)
        #expect(full.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil)
    }

    @Test func diagnosticsNeverShowAFullToken() {
        #expect(DeviceToken.redacted("0123456789abcdef") == "…abcdef")
        #expect(!DeviceToken.redacted("0123456789abcdef").contains("0123"))
        #expect(DeviceToken.redacted("abc") == "…")
    }

    @Test func aTapPayloadYieldsTheChoreID() {
        let id = UUID()
        #expect(PushPayload.choreID(from: ["choreId": id.uuidString, "aps": ["alert": "x"]]) == id)
        #expect(PushPayload.choreID(from: ["choreId": id.uuidString.lowercased()]) == id)
        #expect(PushPayload.choreID(from: [:]) == nil)
        #expect(PushPayload.choreID(from: ["choreId": "not-a-uuid"]) == nil)
        #expect(PushPayload.choreID(from: ["choreId": 42]) == nil)
    }

    @Test func eventNamesMatchTheBackend() {
        #expect(PushEvent.choreAssigned.rawValue == "chore-assigned")
        #expect(PushEvent.choreUpdated.rawValue == "chore-updated")
        #expect(PushEvent.commentCreated.rawValue == "comment-created")
        #expect(PushEvent.statusChanged.rawValue == "status-changed")
    }
}

@MainActor
struct PushRegistrationModelTests {
    struct World {
        let permission: FixtureNotificationPermission
        let registry: FixtureNotificationDeviceRegistry
        let model: PushRegistrationModel
        let remoteRegistrations: LockedState<Int>
        let defaults: UserDefaults
    }

    private func makeWorld(_ status: NotificationAuthorization = .notDetermined, answer: NotificationAuthorization = .authorized) -> World {
        let suite = "push-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let permission = FixtureNotificationPermission(current: status, answerToRequest: answer)
        let registry = FixtureNotificationDeviceRegistry()
        let calls = LockedState(0)
        let model = PushRegistrationModel(
            permission: permission, registry: registry,
            requestRemoteRegistration: { calls.withLock { $0 += 1 } }, defaults: defaults
        )
        return World(permission: permission, registry: registry, model: model, remoteRegistrations: calls, defaults: defaults)
    }

    private let token = Data((0..<32).map { UInt8($0) })
    private var tokenHex: String { DeviceToken.hex(from: token) }

    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    // MARK: permission

    @Test func turningNotificationsOnShowsThePromptAndRegistersWithTheSystem() async {
        let world = makeWorld()
        await world.model.enableNotifications()
        #expect(world.model.authorization == .authorized)
        #expect(await world.permission.requestCount == 1)
        #expect(world.remoteRegistrations.withLock { $0 } == 1)
    }

    @Test func aRefusedPromptStaysDeniedAndNeverRegisters() async {
        let world = makeWorld(answer: .denied)
        await world.model.enableNotifications()
        #expect(world.model.authorization == .denied)
        #expect(world.remoteRegistrations.withLock { $0 } == 0)
    }

    @Test func tappingTurnOnTwiceAsksOnce() async {
        let world = makeWorld()
        let model = world.model   // capture the model, not the whole test fixture (it isn't Sendable)
        async let first: Void = model.enableNotifications()
        async let second: Void = model.enableNotifications()
        _ = await (first, second)
        #expect(await world.permission.requestCount == 1)
    }

    // MARK: registration lifecycle

    @Test func aTokenThatArrivesBeforeSignInIsHeldThenRegisteredOnSignIn() async {
        let world = makeWorld(.authorized)
        world.model.didReceiveDeviceToken(token)
        #expect(await world.registry.registered.isEmpty, "nobody is signed in yet")

        await world.model.sessionDidSignIn()
        #expect(await world.registry.registered == [tokenHex])
        #expect(world.model.registration == .registered)
    }

    @Test func aTokenThatArrivesAfterSignInIsRegisteredStraightAway() async {
        let world = makeWorld(.authorized)
        await world.model.sessionDidSignIn()
        world.model.didReceiveDeviceToken(token)
        #expect(await waitUntil { await world.registry.registered == [tokenHex] })
        #expect(world.model.registration == .registered)
    }

    @Test func signingInAsksTheSystemToRegisterAgainEveryTime() async {
        let world = makeWorld(.authorized)
        await world.model.sessionDidSignIn()
        world.model.sessionDidSignOut()
        await world.model.sessionDidSignIn()
        #expect(world.remoteRegistrations.withLock { $0 } == 2)
    }

    @Test func nothingRegistersWithoutPermission() async {
        for status in [NotificationAuthorization.notDetermined, .denied] {
            let world = makeWorld(status)
            world.model.didReceiveDeviceToken(token)
            await world.model.sessionDidSignIn()
            #expect(await world.registry.registered.isEmpty)
            #expect(world.remoteRegistrations.withLock { $0 } == 0)
        }
    }

    @Test func theSameTokenIsNotRegisteredTwiceInARow() async {
        let world = makeWorld(.authorized)
        await world.model.sessionDidSignIn()
        world.model.didReceiveDeviceToken(token)
        #expect(await waitUntil { world.model.registration == .registered })
        world.model.didReceiveDeviceToken(token)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await world.registry.registered == [tokenHex])
    }

    @Test func aFailedRegistrationIsShownAndCanBeRetried() async {
        let world = makeWorld(.authorized)
        await world.registry.failNextRegister()
        world.model.didReceiveDeviceToken(token)
        await world.model.sessionDidSignIn()
        guard case .failed = world.model.registration else { Issue.record("expected failed"); return }

        await world.model.retry()
        #expect(world.model.registration == .registered)
        #expect(await world.registry.registered == [tokenHex])
    }

    @Test func aSystemRegistrationFailureIsReported() {
        let world = makeWorld(.authorized)
        world.model.didFailToRegisterForRemoteNotifications()
        guard case .failed = world.model.registration else { Issue.record("expected failed"); return }
    }

    // MARK: sign-out

    @Test func signingOutRemovesThisDeviceFromTheUser() async {
        let world = makeWorld(.authorized)
        world.model.didReceiveDeviceToken(token)
        await world.model.sessionDidSignIn()

        await world.model.unregisterBeforeSignOut()
        #expect(await world.registry.unregistered == [tokenHex])
        #expect(world.model.registration == .notRegistered)
    }

    @Test func aFailedUnregisterDoesNotThrowOrBlock() async {
        let world = makeWorld(.authorized)
        world.model.didReceiveDeviceToken(token)
        await world.model.sessionDidSignIn()
        await world.registry.failNextUnregister()
        await world.model.unregisterBeforeSignOut()   // must simply return
        #expect(world.model.registration == .notRegistered)
    }

    @Test func signingOutWithNothingRegisteredMakesNoCall() async {
        let world = makeWorld(.authorized)
        await world.model.unregisterBeforeSignOut()
        #expect(await world.registry.unregistered.isEmpty)
    }

    // MARK: home prompt

    @Test func thePromptShowsOnlyWhileUndecidedAndNotDismissed() async {
        let world = makeWorld()
        await world.model.refreshAuthorization()
        #expect(world.model.shouldShowHomePrompt)

        world.model.dismissPrompt()
        #expect(!world.model.shouldShowHomePrompt)
        #expect(world.defaults.bool(forKey: PushRegistrationModel.promptDismissedKey), "the choice is remembered")

        for status in [NotificationAuthorization.authorized, .denied] {
            let other = makeWorld(status)
            await other.model.refreshAuthorization()
            #expect(!other.model.shouldShowHomePrompt)
        }
    }

    @Test func aDismissedPromptStaysDismissedAfterRelaunch() {
        let world = makeWorld()
        world.model.dismissPrompt()
        let relaunched = PushRegistrationModel(
            permission: world.permission, registry: world.registry, requestRemoteRegistration: {}, defaults: world.defaults
        )
        #expect(relaunched.isPromptDismissed)
    }
}

@MainActor
struct SignOutHookTests {
    @Test func theHookRunsBeforeTheSessionIsCleared() async {
        let auth = FixtureAuthenticating(initialSession: AppSessionRecord(userId: UUID(), email: "a@b.c"))
        let session = AppSession(authenticating: auth)
        await session.restore()
        let stillSignedIn = LockedState<Bool?>(nil)
        session.beforeSignOut = {
            let current = try? await auth.currentSession()
            stillSignedIn.withLock { $0 = (current != nil) }
        }

        await session.signOut()

        #expect(stillSignedIn.withLock { $0 } == true, "authenticated calls are still possible inside the hook")
        #expect(session.phase == .signedOut(reason: nil))
    }

    @Test func aHungHookNeverBlocksSigningOut() async {
        let auth = FixtureAuthenticating(initialSession: AppSessionRecord(userId: UUID(), email: "a@b.c"))
        let session = AppSession(authenticating: auth)
        await session.restore()
        session.beforeSignOutTimeout = .milliseconds(100)
        session.beforeSignOut = { try? await Task.sleep(for: .seconds(30)) }

        let started = ContinuousClock.now
        await session.signOut()

        #expect(ContinuousClock.now - started < .seconds(5), "sign-out gave up waiting for the hook")
        #expect(session.phase == .signedOut(reason: nil))
    }
}

@MainActor
struct PushBridgeTests {
    @Test func aTapThatArrivesBeforeTheAppIsReadyIsDeliveredWhenItIs() {
        let bridge = PushBridge()
        let id = UUID()
        bridge.openChore(id)                       // cold launch from a notification tap

        var received: [UUID] = []
        bridge.onOpenChore = { received.append($0) }
        #expect(received == [id])

        bridge.openChore(id)                       // and later taps go straight through
        #expect(received == [id, id])
    }

    @Test func aTokenThatArrivesEarlyIsDeliveredOnceAHandlerIsAttached() {
        let bridge = PushBridge()
        bridge.deviceToken(Data([1, 2, 3]))
        var received: [Data] = []
        bridge.onDeviceToken = { received.append($0) }
        #expect(received == [Data([1, 2, 3])])
        bridge.onDeviceToken = { received.append($0) }   // re-attaching must not replay it
        #expect(received.count == 1)
    }
}
