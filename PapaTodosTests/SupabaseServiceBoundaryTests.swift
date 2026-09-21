import Auth
import Foundation
import Supabase
import Testing
@testable import PapaTodos

/// Exercises the live repositories against a stubbed transport: request shape,
/// decoding, and error mapping, without touching the network.
@Suite(.serialized)
struct SupabaseServiceBoundaryTests {
    func makeClient() -> SupabaseClient {
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

}

extension SupabaseServiceBoundaryTests {
    private static let profileRow = ##"[{"id":"22222222-2222-2222-2222-222222222222","full_name":"Mum","avatar_url":"https://e.com/a.png","personalisation":{"theme":"#111111","other":"keep"}}]"##

    @Test func avatarUpdateTargetsOneRowAndSendsOnlyTheAvatar() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: Self.profileRow)
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let profile = try await SupabaseProfileRepository(client: makeClient())
            .updateAvatarURL(id: id, to: URL(string: "https://e.com/a.png"))

        #expect(profile.avatarURL?.host == "e.com")
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.method == "PATCH")
        #expect(request.url.path == "/rest/v1/profiles")
        #expect(request.url.query?.contains("id=eq.\(id.uuidString.lowercased())") == true)
        #expect(request.bodyJSON?.keys.sorted() == ["avatar_url"])
        #expect(request.bodyJSON?["avatar_url"] as? String == "https://e.com/a.png")
    }

    @Test func clearingTheAvatarSendsNull() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: Self.profileRow)
        _ = try await SupabaseProfileRepository(client: makeClient()).updateAvatarURL(id: UUID(), to: nil)
        let body = try #require(StubURLProtocol.recorded.first?.bodyJSON)
        #expect(body["avatar_url"] is NSNull)
    }

    @Test func themeUpdateMergesIntoExistingPersonalisation() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respondInOrder([
            (200, ##"[{"personalisation":{"theme":"#000000","other":"keep"}}]"##),
            (200, Self.profileRow),
        ])
        _ = try await SupabaseProfileRepository(client: makeClient()).updateThemeColor(id: UUID(), to: "#123456")

        let requests = StubURLProtocol.recorded
        #expect(requests.map(\.method) == ["GET", "PATCH"])
        let personalisation = try #require(requests[1].bodyJSON?["personalisation"] as? [String: Any])
        #expect(personalisation["theme"] as? String == "#123456")
        #expect(personalisation["other"] as? String == "keep")
    }

    @Test func updateThatChangesNoRowsIsAFailureNotASilentSuccess() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "[]")
        await #expect(throws: DataServiceError.server) {
            _ = try await SupabaseProfileRepository(client: makeClient()).updateAvatarURL(id: UUID(), to: nil)
        }
    }

    @Test func aDeleteRefusedByRowLevelSecurityIsReportedNotSilentlySwallowed() async {
        StubURLProtocol.reset()
        // The DELETE "succeeds" with no rows, and the chore is still there when looked up afterwards.
        StubURLProtocol.respondInOrder([(200, "[]"), (200, choreJSON)])
        await #expect(throws: DataServiceError.notCreator) {
            try await SupabaseChoreRepository(client: makeClient()).delete(id: UUID())
        }
        #expect(StubURLProtocol.recorded.map(\.method) == ["DELETE", "GET"])
    }

    @Test func deletingAChoreThatIsAlreadyGoneIsNotAnError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respondInOrder([(200, "[]"), (200, "[]")])
        try await SupabaseChoreRepository(client: makeClient()).delete(id: UUID())
    }

    @Test func aSuccessfulDeleteDoesNotLookTheChoreUpAgain() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: #"[{"id":"11111111-1111-1111-1111-111111111111"}]"#)
        try await SupabaseChoreRepository(client: makeClient()).delete(id: UUID())
        #expect(StubURLProtocol.recorded.map(\.method) == ["DELETE"])
    }

    @Test func cancelledRequestsAreNotReportedAsServerErrors() async {
        StubURLProtocol.reset()
        StubURLProtocol.fail(with: URLError(.cancelled))
        await #expect(throws: DataServiceError.cancelled) {
            _ = try await SupabaseChoreRepository(client: makeClient()).fetchChores()
        }
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
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let body: Data?
        var bodyJSON: [String: Any]? { body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }

    private struct State {
        var responses: [(status: Int, body: Data)] = [(200, Data())]
        var failure: URLError?
        var lastRequest: URLRequest?
        var recorded: [Recorded] = []
    }
    private static let state = LockedState(State())

    static var lastRequest: URLRequest? { state.withLock { $0.lastRequest } }
    static var recorded: [Recorded] { state.withLock { $0.recorded } }

    static func reset() {
        state.withLock { $0 = State() }
    }

    static func respond(status: Int, body: String) {
        state.withLock { $0 = State(responses: [(status, Data(body.utf8))]) }
    }

    /// Serves the responses in order; the last one repeats.
    static func respondInOrder(_ responses: [(status: Int, body: String)]) {
        state.withLock { $0 = State(responses: responses.map { ($0.status, Data($0.body.utf8)) }) }
    }

    static func fail(with error: URLError) {
        state.withLock { $0 = State(failure: error) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(of: request)
        let (response, failure) = Self.state.withLock { state -> ((status: Int, body: Data), URLError?) in
            state.lastRequest = request
            state.recorded.append(Recorded(method: request.httpMethod ?? "GET", url: request.url!, body: body))
            let next = state.responses.count > 1 ? state.responses.removeFirst() : state.responses[0]
            return (next, state.failure)
        }
        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let http = HTTPURLResponse(
            url: request.url!, statusCode: response.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` hands request bodies to protocols as a stream, not `httpBody`.
    private static func readBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
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
