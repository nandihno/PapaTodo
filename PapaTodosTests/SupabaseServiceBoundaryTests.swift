import Auth
import Foundation
import Supabase
import Testing
@testable import PapaTodos

/// Exercises the live repositories against a stubbed transport: request shape,
/// decoding, and error mapping, without touching the network.
@Suite(.serialized)
struct SupabaseServiceBoundaryTests {
    private func makeClient() -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return SupabaseClient(
            supabaseURL: URL(string: "https://stub.supabase.test")!,
            supabaseKey: "sb_publishable_test",
            options: SupabaseClientOptions(global: .init(session: URLSession(configuration: configuration)))
        )
    }

    private let choreJSON = """
    [{"id": "11111111-1111-1111-1111-111111111111", "title": "Bins", "description": null,
      "assigned_to": null, "created_by": null, "status": "pending", "due_date": null,
      "image_url": null, "created_at": "2026-09-18T10:15:30+00:00", "updated_at": "2026-09-18T10:15:30+00:00",
      "assignedProfile": null, "createdProfile": null, "attachments": []}]
    """

    @Test func fetchChoresRequestsRelationalSelectAndDecodes() async throws {
        StubURLProtocol.respond(status: 200, body: choreJSON)
        let repository = SupabaseChoreRepository(client: makeClient())

        let chores = try await repository.fetchChores()

        #expect(chores.map(\.title) == ["Bins"])
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.path == "/rest/v1/chores")
        let select = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "select" }?.value ?? ""
        #expect(select.contains("profiles!chores_assigned_to_fkey"))
        #expect(select.contains("chore_attachments"))
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
    }

    @Test func fetchChoreByIDReturnsNilWhenNoRows() async throws {
        StubURLProtocol.respond(status: 200, body: "[]")
        let repository = SupabaseChoreRepository(client: makeClient())
        #expect(try await repository.fetchChore(id: UUID()) == nil)
    }

    @Test func unauthorizedResponseMapsToSessionExpired() async {
        StubURLProtocol.respond(status: 401, body: #"{"code":"PGRST301","message":"JWT expired"}"#)
        let repository = SupabaseChoreRepository(client: makeClient())
        await #expect(throws: DataServiceError.sessionExpired) {
            _ = try await repository.fetchChores()
        }
    }

    @Test func serverFailureMapsToServerError() async {
        StubURLProtocol.respond(status: 500, body: #"{"message":"boom"}"#)
        let repository = SupabaseChoreRepository(client: makeClient())
        await #expect(throws: DataServiceError.server) {
            _ = try await repository.fetchChores()
        }
    }

    @Test func connectivityFailureMapsToOffline() async {
        StubURLProtocol.fail(with: URLError(.notConnectedToInternet))
        let repository = SupabaseChoreRepository(client: makeClient())
        await #expect(throws: DataServiceError.offline) {
            _ = try await repository.fetchChores()
        }
    }

    @Test func profileRepositoryDecodesProfile() async throws {
        StubURLProtocol.respond(status: 200, body: #"[{"id":"22222222-2222-2222-2222-222222222222","full_name":"Mum","avatar_url":null,"personalisation":{}}]"#)
        let repository = SupabaseProfileRepository(client: makeClient())
        let profile = try await repository.fetchProfile(id: UUID())
        #expect(profile?.fullName == "Mum")
    }

    @Test func commentRepositoryOrdersByCreatedAt() async throws {
        StubURLProtocol.respond(status: 200, body: "[]")
        let repository = SupabaseCommentRepository(client: makeClient())
        _ = try await repository.fetchComments(choreID: UUID())
        let query = StubURLProtocol.lastRequest?.url?.query ?? ""
        #expect(query.contains("order=created_at.asc"))
    }

    @Test func writesAreNotAvailableInPhase1() async {
        StubURLProtocol.reset()
        let repository = SupabaseChoreRepository(client: makeClient())
        let draft = ChoreDraft(title: "x", description: nil, assignedTo: nil, status: .pending, dueDate: nil)
        await #expect(throws: DataServiceError.notAvailableYet) { _ = try await repository.create(draft) }
        await #expect(throws: DataServiceError.notAvailableYet) { try await repository.delete(id: UUID()) }
        await #expect(throws: DataServiceError.notAvailableYet) {
            try await repository.updateStatus(id: UUID(), status: .done)
        }
        // Nothing should have reached the network.
        #expect(StubURLProtocol.lastRequest == nil)
    }
}

struct SupabaseErrorMapperTests {
    @Test func sessionMissingMapsToExpired() {
        #expect(SupabaseErrorMapper.map(AuthError.sessionMissing) == .sessionExpired)
    }

    @Test func urlErrorsMapByConnectivity() {
        #expect(SupabaseErrorMapper.map(URLError(.timedOut)) == .offline)
        #expect(SupabaseErrorMapper.map(URLError(.badServerResponse)) == .server)
    }

    @Test func authAPIErrorsMapByCode() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://stub.supabase.test")!, statusCode: 400, httpVersion: nil, headerFields: nil
        ))
        func apiError(_ code: ErrorCode) -> AuthError {
            .api(message: "x", errorCode: code, underlyingData: Data(), underlyingResponse: response)
        }
        #expect(SupabaseErrorMapper.map(apiError(.invalidCredentials)) == .invalidCredentials)
        #expect(SupabaseErrorMapper.map(apiError(.refreshTokenNotFound)) == .sessionExpired)
        #expect(SupabaseErrorMapper.map(apiError(.refreshTokenAlreadyUsed)) == .sessionExpired)
    }
}

/// Global URLProtocol stub. The suite is `.serialized` because state is shared.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var status = 200
        var body = Data()
        var failure: URLError?
        var lastRequest: URLRequest?
    }
    private static let state = LockedState(State())

    static var lastRequest: URLRequest? { state.withLock { $0.lastRequest } }

    static func reset() {
        state.withLock { $0 = State() }
    }

    static func respond(status: Int, body: String) {
        state.withLock { $0 = State(status: status, body: Data(body.utf8)) }
    }

    static func fail(with error: URLError) {
        state.withLock { $0 = State(failure: error) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let snapshot = Self.state.withLock { state -> State in
            state.lastRequest = request
            return state
        }
        if let failure = snapshot.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: snapshot.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: snapshot.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LockedState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
