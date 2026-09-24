import Foundation
import Supabase
import Testing
@testable import PapaTodos

private let templateRow = """
{"id":"dddddddd-0000-0000-0000-000000000001","title":"Woolworths run","description":"<ul><li>Milk</li></ul>",
 "assigned_to":null,"sort_order":0,"created_by":"aaaaaaaa-0000-0000-0000-000000000001"}
"""

// An extension of the serialized suite so every test sharing the global URLProtocol stub
// runs one at a time.
extension SupabaseServiceBoundaryTests {
    @Test func favouritesAreReadInSharedOrder() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "[\(templateRow)]")

        let templates = try await SupabaseChoreTemplateRepository(client: makeClient()).fetchTemplates()

        #expect(templates.map(\.title) == ["Woolworths run"])
        #expect(templates.first?.description == "<ul><li>Milk</li></ul>")
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.url.path == "/rest/v1/chore_templates")
        let order = request.url.query?.removingPercentEncoding ?? ""
        #expect(order.contains("order=sort_order.asc"))
        #expect(order.contains("created_at.asc"))
    }

    @Test func aNewFavouriteSendsItsFieldsButNeverItsCreator() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 201, body: templateRow)
        let assignee = UUID()

        _ = try await SupabaseChoreTemplateRepository(client: makeClient()).create(
            ChoreTemplateDraft(title: "  Woolworths run ", description: "<ul><li>Milk</li></ul>", assignedTo: assignee), sortOrder: 3
        )

        let request = try #require(StubURLProtocol.recorded.first { $0.method == "POST" })
        let body = try #require(request.bodyJSON)
        #expect(body["title"] as? String == "Woolworths run")
        #expect(body["description"] as? String == "<ul><li>Milk</li></ul>")
        #expect(body["assigned_to"] as? String == assignee.uuidString.lowercased())
        #expect(body["sort_order"] as? Int == 3)
        #expect(body["created_by"] == nil)
    }

    @Test func aTitleTakenInTheDatabaseIsADuplicate() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 409, body: #"{"code":"23505","message":"duplicate key value violates unique constraint \"chore_templates_title_key\""}"#)
        await #expect(throws: DataServiceError.duplicate) {
            _ = try await SupabaseChoreTemplateRepository(client: makeClient()).create(
                ChoreTemplateDraft(title: "Woolworths run", description: nil, assignedTo: nil), sortOrder: 0
            )
        }
    }

    @Test func editingAFavouriteThatIsGoneIsNotFound() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 200, body: "[]")
        let id = UUID()
        await #expect(throws: DataServiceError.notFound) {
            _ = try await SupabaseChoreTemplateRepository(client: makeClient()).update(
                id: id, with: ChoreTemplateDraft(title: "Bins", description: nil, assignedTo: nil)
            )
        }
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.method == "PATCH")
        #expect(request.url.query?.lowercased().contains("id=eq.\(id.uuidString.lowercased())") == true)
        #expect(request.bodyJSON?["created_by"] == nil)
        #expect(request.bodyJSON?["sort_order"] == nil)
    }

    @Test func reorderingWritesOneRowPerMovedFavourite() async throws {
        StubURLProtocol.reset()
        let first = UUID(), second = UUID()

        try await SupabaseChoreTemplateRepository(client: makeClient()).updateSortOrders([second: 1, first: 0])

        let patches = StubURLProtocol.recorded.filter { $0.method == "PATCH" }
        #expect(patches.count == 2)
        #expect(patches.map { $0.bodyJSON?["sort_order"] as? Int } == [0, 1])
        #expect(patches.first?.url.query?.lowercased().contains(first.uuidString.lowercased()) == true)
        #expect(patches.allSatisfy { $0.bodyJSON?.keys.sorted() == ["sort_order"] })
    }

    @Test func deletingAFavouriteTargetsOneRow() async throws {
        StubURLProtocol.reset()
        let id = UUID()
        try await SupabaseChoreTemplateRepository(client: makeClient()).delete(id: id)
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.method == "DELETE")
        #expect(request.url.path == "/rest/v1/chore_templates")
        #expect(request.url.query?.lowercased().contains("id=eq.\(id.uuidString.lowercased())") == true)
    }
}
