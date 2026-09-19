import Foundation
import Testing
@testable import PapaTodos

/// Opt-in live read check against the real backend under authenticated RLS.
///
/// Skipped unless `PB_TEST_EMAIL` and `PB_TEST_PASSWORD` are set. Pass them to
/// `xcodebuild` as `TEST_RUNNER_PB_TEST_EMAIL=... TEST_RUNNER_PB_TEST_PASSWORD=...`
/// so they only exist in the test process environment and are never written to
/// the repo. Read-only: signs in, reads, signs out.
@Suite(.serialized)
@MainActor
struct LiveBackendReadTests {
    nonisolated fileprivate static let email = ProcessInfo.processInfo.environment["PB_TEST_EMAIL"]
    nonisolated fileprivate static let password = ProcessInfo.processInfo.environment["PB_TEST_PASSWORD"]
    nonisolated fileprivate static var isConfigured: Bool { email?.isEmpty == false && password?.isEmpty == false }

    @Test(.enabled(if: LiveBackendReadTests.isConfigured))
    func signedInFamilyAccountCanReadProfileAndChoresUnderRLS() async throws {
        let environment = AppEnvironment.live(configuration: try AppConfiguration.load())

        try await environment.authenticating.signIn(
            email: try #require(Self.email), password: try #require(Self.password)
        )
        let record = try #require(try await environment.authenticating.currentSession())

        let profile = try await environment.profileRepository.fetchProfile(id: record.userId)
        let profiles = try await environment.profileRepository.fetchProfiles()
        let chores = try await environment.choreRepository.fetchChores()

        #expect(profile != nil)
        #expect(!profiles.isEmpty)
        // Every embedded reference decoded; count only, never log titles/bodies.
        print("LIVE-READ: profile=\(profile != nil) profiles=\(profiles.count) chores=\(chores.count)")

        if let first = chores.first {
            let comments = try await environment.commentRepository.fetchComments(choreID: first.id)
            print("LIVE-READ: comments(first chore)=\(comments.count)")
        }

        try await environment.authenticating.signOut()
        #expect(try await environment.authenticating.currentSession() == nil)
    }
}
