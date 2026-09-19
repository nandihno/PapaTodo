import Foundation
import Testing
@testable import PapaTodos

@MainActor
struct FixtureRepositoryTests {
    @Test func chorRepositorySupportsFullCRUDDeterministically() async throws {
        let repository = FixtureChoreRepository(chores: [])

        let created = try await repository.create(ChoreDraft(
            title: "New chore", description: "Details", assignedTo: nil,
            status: .pending, dueDate: nil
        ))
        #expect(try await repository.fetchChores().count == 1)
        #expect(try await repository.fetchChore(id: created.id) == created)

        let updated = try await repository.update(id: created.id, patch: ChorePatch(title: "Renamed", status: .inProgress))
        #expect(updated.title == "Renamed")
        #expect(updated.status == .inProgress)

        try await repository.updateStatus(id: created.id, status: .done)
        let afterStatusUpdate = try await repository.fetchChore(id: created.id)
        #expect(afterStatusUpdate?.status == .done)

        try await repository.delete(id: created.id)
        #expect(try await repository.fetchChores().isEmpty)
    }

    @Test func chorRepositoryThrowsForUnknownID() async {
        let repository = FixtureChoreRepository(chores: [])
        await #expect(throws: FixtureChoreRepository.RepositoryError.self) {
            try await repository.updateStatus(id: UUID(), status: .done)
        }
    }

    @Test func authenticatingRejectsWrongCredentials() async {
        let authenticating = FixtureAuthenticating(validEmail: "a@b.com", validPassword: "secret")
        await #expect(throws: DataServiceError.invalidCredentials) {
            try await authenticating.signIn(email: "a@b.com", password: "wrong")
        }
        let session = try? await authenticating.currentSession()
        #expect(session == nil)
    }

    @Test func authenticatingAcceptsCorrectCredentialsAndSignsOut() async throws {
        let authenticating = FixtureAuthenticating(validEmail: "a@b.com", validPassword: "secret")
        try await authenticating.signIn(email: "a@b.com", password: "secret")
        #expect(try await authenticating.currentSession() != nil)

        try await authenticating.signOut()
        #expect(try await authenticating.currentSession() == nil)
    }

    @Test func commentRepositoryValidatesAndStoresComments() async throws {
        let repository = FixtureCommentRepository()
        let choreID = UUID()

        await #expect(throws: FixtureCommentRepository.ValidationError.self) {
            try await repository.addComment(choreID: choreID, body: "   ")
        }

        try await repository.addComment(choreID: choreID, body: "  Looks good  ")
        let comments = try await repository.fetchComments(choreID: choreID)
        #expect(comments.count == 1)
        #expect(comments[0].body == "Looks good")
    }
}
