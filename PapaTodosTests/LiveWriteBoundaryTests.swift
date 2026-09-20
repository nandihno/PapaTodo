import Auth
import Foundation
import Supabase
import Testing
@testable import PapaTodos

/// Serves a fixed session so the live repositories can read the signed-in user's id
/// (creator, attachment owner, storage prefix) without any network call.
private let testStorageKey = "stub-session"

private final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    init(session: Session) throws {
        values = [testStorageKey: try AuthClient.Configuration.jsonEncoder.encode(session)]
    }
    /// No saved session at all.
    init() { values = [:] }
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}

private let signedInUserID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

private func makeSignedInClient() throws -> SupabaseClient {
    let json = """
    {"access_token":"stub","token_type":"bearer","expires_in":3600,"expires_at":\(Int(Date().timeIntervalSince1970) + 3600),
     "refresh_token":"stub","user":{"id":"\(signedInUserID.uuidString)","aud":"authenticated","app_metadata":{},"user_metadata":{},
     "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}}
    """
    let session = try AuthClient.Configuration.jsonDecoder.decode(Session.self, from: Data(json.utf8))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return SupabaseClient(
        supabaseURL: URL(string: "https://stub.supabase.test")!,
        supabaseKey: "sb_publishable_test",
        options: SupabaseClientOptions(
            auth: .init(storage: try MemoryAuthStorage(session: session), storageKey: testStorageKey, emitLocalSessionAsInitialSession: true),
            global: .init(session: URLSession(configuration: configuration))
        )
    )
}

private let choreRow = """
{"id":"11111111-1111-1111-1111-111111111111","title":"T","description":null,"assigned_to":null,"created_by":"aaaaaaaa-0000-0000-0000-000000000001",
 "status":"pending","due_date":null,"image_url":null,"created_at":"2026-09-19T00:00:00+00:00","updated_at":"2026-09-19T00:00:00+00:00",
 "assignedProfile":null,"createdProfile":null,"attachments":[]}
"""

// An extension of the serialized suite so every test sharing the global URLProtocol stub
// runs one at a time (separate suites would run in parallel and trample each other).
extension SupabaseServiceBoundaryTests {
    // MARK: chores

    @Test func createSetsTheCreatorFromTheSessionAndSendsEveryField() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 201, body: choreRow)
        let assignee = UUID()
        let due = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try await SupabaseChoreRepository(client: try makeSignedInClient()).create(
            ChoreDraft(title: "Bins", description: "<p>x</p>", assignedTo: assignee, status: .inProgress, dueDate: due,
                       imageURL: URL(string: "https://e.com/a.jpg"))
        )

        let request = try #require(StubURLProtocol.recorded.first { $0.method == "POST" })
        #expect(request.url.path == "/rest/v1/chores")
        let body = try #require(request.bodyJSON)
        #expect(body["created_by"] as? String == signedInUserID.uuidString.lowercased())
        #expect(body["title"] as? String == "Bins")
        #expect(body["status"] as? String == "in_progress")
        #expect(body["assigned_to"] as? String == assignee.uuidString.lowercased())
        #expect(body["image_url"] as? String == "https://e.com/a.jpg")
        #expect((body["due_date"] as? String)?.hasSuffix("Z") == true)
    }

    @Test func writesWithoutASignedInUserNeverReachTheNetwork() async throws {
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://stub.supabase.test")!, supabaseKey: "k",
            options: SupabaseClientOptions(
                auth: .init(storage: MemoryAuthStorage(), storageKey: testStorageKey, emitLocalSessionAsInitialSession: true),
                global: .init(session: URLSession(configuration: configuration))
            )
        )

        // Each of these must refuse to run as "nobody" rather than send an unowned row.
        await #expect(throws: DataServiceError.sessionExpired) {
            _ = try await SupabaseChoreRepository(client: client).create(
                ChoreDraft(title: "x", description: nil, assignedTo: nil, status: .pending, dueDate: nil)
            )
        }
        await #expect(throws: DataServiceError.sessionExpired) {
            _ = try await SupabaseAttachmentRepository(client: client).insert(
                [NewAttachment(storagePath: "u/p.jpg", publicURL: URL(string: "https://e.com/p.jpg")!, fileName: "p", mimeType: "image/jpeg", sortOrder: 0)],
                choreID: UUID()
            )
        }
        await #expect(throws: DataServiceError.sessionExpired) {
            _ = try await SupabaseAttachmentStorage(client: client).upload(PhotoUpload(data: Data([1]), fileName: "a.jpg", mimeType: "image/jpeg"))
        }
        #expect(StubURLProtocol.recorded.isEmpty)
    }

    @Test func updateSendsOnlyTheChangedFieldsAndNeverTheCreator() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "[\(choreRow)]")
        let id = UUID()

        _ = try await SupabaseChoreRepository(client: try makeSignedInClient()).update(
            id: id, patch: ChorePatch(title: "Renamed", description: .some(nil))
        )

        let request = try #require(StubURLProtocol.recorded.first { $0.method == "PATCH" })
        #expect(request.url.query?.lowercased().contains("id=eq.\(id.uuidString.lowercased())") == true)
        let body = try #require(request.bodyJSON)
        #expect(body.keys.sorted() == ["description", "title"])
        #expect(body["description"] is NSNull)
        #expect(body["created_by"] == nil)
        #expect(body["due_date"] == nil)
    }

    @Test func anEmptyPatchMakesNoWrite() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "[\(choreRow)]")
        _ = try await SupabaseChoreRepository(client: try makeSignedInClient()).update(id: UUID(), patch: ChorePatch())
        #expect(!StubURLProtocol.recorded.contains { $0.method == "PATCH" })
    }

    @Test func deleteTargetsOneRowByID() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: #"[{"id":"11111111-1111-1111-1111-111111111111"}]"#)
        let id = UUID()
        try await SupabaseChoreRepository(client: try makeSignedInClient()).delete(id: id)
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.method == "DELETE")
        #expect(request.url.query?.lowercased().contains("id=eq.\(id.uuidString.lowercased())") == true)
    }

    // MARK: attachments

    @Test func attachmentRowsAreOwnedByTheSessionUser() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 201, body: #"[{"id":"22222222-2222-2222-2222-222222222222"}]"#)
        let choreID = UUID()

        let ids = try await SupabaseAttachmentRepository(client: try makeSignedInClient()).insert(
            [NewAttachment(storagePath: "u/p.jpg", publicURL: URL(string: "https://e.com/p.jpg")!, fileName: "p.jpg", mimeType: "image/jpeg", sortOrder: 3)],
            choreID: choreID
        )

        #expect(ids.count == 1)
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.url.path == "/rest/v1/chore_attachments")
        let bodyData = try #require(request.body)
        let rows = try #require(JSONSerialization.jsonObject(with: bodyData) as? [[String: Any]])
        #expect(rows.first?["created_by"] as? String == signedInUserID.uuidString.lowercased())
        #expect(rows.first?["chore_id"] as? String == choreID.uuidString.lowercased())
        #expect(rows.first?["sort_order"] as? Int == 3)
    }

    @Test func aRowLevelSecurityRefusalOnInsertIsNotPermitted() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 403, body: #"{"code":"42501","message":"new row violates row-level security policy for table \"chore_attachments\""}"#)
        await #expect(throws: DataServiceError.notPermitted) {
            _ = try await SupabaseAttachmentRepository(client: try makeSignedInClient()).insert(
                [NewAttachment(storagePath: "u/p.jpg", publicURL: URL(string: "https://e.com/p.jpg")!, fileName: "p", mimeType: "image/jpeg", sortOrder: 0)],
                choreID: UUID()
            )
        }
    }

    @Test func aDeleteThatRemovesFewerRowsThanRequestedIsNotPermitted() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "[]")   // RLS filtered every row: no error, nothing deleted
        await #expect(throws: DataServiceError.notPermitted) {
            try await SupabaseAttachmentRepository(client: try makeSignedInClient()).delete(ids: [UUID()])
        }
    }

    // MARK: storage

    @Test func uploadUsesTheSessionUsersPrefixAndReturnsAPublicURL() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: #"{"Id":"x","Key":"chore-images/whatever"}"#)

        let file = try await SupabaseAttachmentStorage(client: try makeSignedInClient()).upload(
            PhotoUpload(data: Data([1, 2, 3]), fileName: "pic.jpg", mimeType: "image/jpeg")
        )

        let prefix = signedInUserID.uuidString.lowercased() + "/"
        #expect(file.storagePath.hasPrefix(prefix))
        #expect(file.storagePath.hasSuffix("-pic.jpg"))
        #expect(file.publicURL.path.contains("/storage/v1/object/public/chore-images/"))
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.method == "POST")
        #expect(request.url.path.hasPrefix("/storage/v1/object/chore-images/\(prefix)"))
    }

    @Test func removeReportsOnlyWhatStorageActuallyDeleted() async throws {
        StubURLProtocol.reset()
        // This is what the live bucket does today: no DELETE policy, so nothing is removed and no error is raised.
        StubURLProtocol.respond(status: 200, body: "[]")
        let removed = try await SupabaseAttachmentStorage(client: try makeSignedInClient()).remove(paths: ["u/a.jpg"])
        #expect(removed.isEmpty)
        #expect(StubURLProtocol.recorded.first?.method == "DELETE")
    }

    @Test func aStorageForbiddenResponseIsNotPermitted() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 403, body: #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#)
        await #expect(throws: DataServiceError.notPermitted) {
            _ = try await SupabaseAttachmentStorage(client: try makeSignedInClient()).upload(
                PhotoUpload(data: Data([1]), fileName: "a.jpg", mimeType: "image/jpeg")
            )
        }
    }

    // MARK: status (Phase 4)

    @Test func aStatusChangeSendsOnlyTheStatusForOneChore() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: #"[{"id":"11111111-1111-1111-1111-111111111111"}]"#)
        let id = UUID()

        try await SupabaseChoreRepository(client: try makeSignedInClient()).updateStatus(id: id, status: .inProgress)

        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.method == "PATCH")
        #expect(request.url.query?.lowercased().contains("id=eq.\(id.uuidString.lowercased())") == true)
        #expect(request.bodyJSON?.keys.sorted() == ["status"])
        #expect(request.bodyJSON?["status"] as? String == "in_progress")
    }

    @Test func aStatusChangeThatChangesNoRowsIsAFailure() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "[]")
        await #expect(throws: DataServiceError.server) {
            try await SupabaseChoreRepository(client: try makeSignedInClient()).updateStatus(id: UUID(), status: .done)
        }
    }

    // MARK: comments (Phase 4)

    private static let commentRow = #"{"id":"33333333-3333-3333-3333-333333333333","chore_id":"11111111-1111-1111-1111-111111111111","author_id":"aaaaaaaa-0000-0000-0000-000000000001","body":"hi","created_at":"2026-09-20T01:02:03.456789+00:00"}"#

    @Test func aCommentIsAuthoredByTheSessionUserAndTrimmed() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 201, body: Self.commentRow)
        let choreID = UUID()

        let stored = try await SupabaseCommentRepository(client: try makeSignedInClient()).addComment(choreID: choreID, body: "  hi  ")

        #expect(stored.body == "hi")
        let request = try #require(StubURLProtocol.recorded.first { $0.method == "POST" })
        #expect(request.url.path == "/rest/v1/chore_comments")
        let body = try #require(request.bodyJSON)
        #expect(body["author_id"] as? String == signedInUserID.uuidString.lowercased())
        #expect(body["chore_id"] as? String == choreID.uuidString.lowercased())
        #expect(body["body"] as? String == "hi")
        #expect(body.keys.sorted() == ["author_id", "body", "chore_id"])
    }

    @Test func aBlankCommentNeverReachesTheNetwork() async throws {
        StubURLProtocol.reset()
        await #expect(throws: DataServiceError.self) {
            _ = try await SupabaseCommentRepository(client: try makeSignedInClient()).addComment(choreID: UUID(), body: "  \n ")
        }
        #expect(StubURLProtocol.recorded.isEmpty)
    }

    // MARK: realtime mapping

    private func record(_ json: String) throws -> [String: AnyJSON] {
        try JSONDecoder().decode([String: AnyJSON].self, from: Data(json.utf8))
    }

    @Test func realtimeInsertsAndUpdatesDecodeIntoComments() throws {
        let row = try record(Self.commentRow)
        guard case .inserted(let inserted)? = RealtimeCommentMapper.inserted(record: row) else { Issue.record("expected insert"); return }
        #expect(inserted.body == "hi")
        #expect(inserted.choreId.uuidString.lowercased() == "11111111-1111-1111-1111-111111111111")
        guard case .updated(let updated)? = RealtimeCommentMapper.updated(record: row) else { Issue.record("expected update"); return }
        #expect(updated.id == inserted.id)
    }

    @Test func aRealtimeDeleteCarriesOnlyTheID() throws {
        let change = RealtimeCommentMapper.deleted(oldRecord: try record(#"{"id":"33333333-3333-3333-3333-333333333333"}"#))
        #expect(change == .deleted(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!))
    }

    @Test func unreadableRealtimeRowsAreDroppedNotFatal() throws {
        #expect(RealtimeCommentMapper.inserted(record: try record(#"{"id":"not-a-uuid","body":5}"#)) == nil)
        #expect(RealtimeCommentMapper.updated(record: [:]) == nil)
        #expect(RealtimeCommentMapper.deleted(oldRecord: [:]) == nil)
        #expect(RealtimeCommentMapper.deleted(oldRecord: try record(#"{"id":"nope"}"#)) == nil)
    }

    // MARK: push notifications (Phase 5)

    @Test func registeringADeviceCallsTheDatabaseFunctionWithTheEnvironmentAndBundle() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "{}")
        let registry = SupabaseNotificationDeviceRegistry(
            client: try makeSignedInClient(), environment: .sandbox, bundleIdentifier: "org.nando.PapaTodos"
        )

        try await registry.register(deviceToken: "0a1b2c3d")

        let request = try #require(StubURLProtocol.recorded.first { $0.method == "POST" })
        #expect(request.url.path == "/rest/v1/rpc/register_notification_device")
        let body = try #require(request.bodyJSON)
        #expect(body["p_device_token"] as? String == "0a1b2c3d")
        #expect(body["p_apns_environment"] as? String == "sandbox")
        #expect(body["p_app_bundle_id"] as? String == "org.nando.PapaTodos")
        #expect(body.keys.count == 3, "no user id is sent: the database function uses the caller's identity")
    }

    @Test func unregisteringUsesTheSameShapeAndTheProductionEnvironment() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "true")
        let registry = SupabaseNotificationDeviceRegistry(
            client: try makeSignedInClient(), environment: .production, bundleIdentifier: "org.nando.PapaTodos"
        )

        try await registry.unregister(deviceToken: "ff00")

        let request = try #require(StubURLProtocol.recorded.first { $0.method == "POST" })
        #expect(request.url.path == "/rest/v1/rpc/unregister_notification_device")
        #expect(request.bodyJSON?["p_apns_environment"] as? String == "production")
    }

    @Test func anAuthenticationFailureRegisteringMapsToSessionExpired() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 401, body: #"{"code":"PGRST301","message":"JWT expired"}"#)
        let registry = SupabaseNotificationDeviceRegistry(
            client: try makeSignedInClient(), environment: .sandbox, bundleIdentifier: "org.nando.PapaTodos"
        )
        await #expect(throws: DataServiceError.sessionExpired) {
            try await registry.register(deviceToken: "0a1b2c3d")
        }
    }

    @Test func theDispatcherPostsTheSameEventAndChoreTheWebSends() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: #"{"sent":1}"#)
        let id = UUID()

        await SupabaseNotificationDispatcher(client: try makeSignedInClient()).notify(.statusChanged, choreID: id)

        let request = try #require(StubURLProtocol.recorded.first { $0.method == "POST" })
        #expect(request.url.path == "/functions/v1/send-push")
        let body = try #require(request.bodyJSON)
        #expect(body["eventType"] as? String == "status-changed")
        #expect(body["choreId"] as? String == id.uuidString.lowercased())
        #expect(body.keys.sorted() == ["choreId", "eventType"], "recipients are decided by the server, never sent from here")
    }

    @Test func aFailingSendPushNeverThrows() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 500, body: #"{"error":"boom"}"#)
        // notify() is non-throwing by design; simply returning proves the failure was contained.
        await SupabaseNotificationDispatcher(client: try makeSignedInClient()).notify(.commentCreated, choreID: UUID())
        StubURLProtocol.fail(with: URLError(.notConnectedToInternet))
        await SupabaseNotificationDispatcher(client: try makeSignedInClient()).notify(.choreUpdated, choreID: UUID())
    }
}
