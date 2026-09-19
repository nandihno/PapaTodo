import Foundation
import PostgREST
import Testing
@testable import PapaTodos

/// Decodes fixtures shaped like PapaBoard's relational selects with the same
/// decoder the Supabase SDK uses for responses.
struct RecordDecodingTests {
    private let decoder = PostgrestClient.Configuration.jsonDecoder

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    @Test func choreDecodesWithEmbeddedProfilesAndAttachments() throws {
        let json = """
        [{
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Take out bins",
          "description": null,
          "assigned_to": "22222222-2222-2222-2222-222222222222",
          "created_by": "33333333-3333-3333-3333-333333333333",
          "status": "in_progress",
          "due_date": "2026-09-20T02:00:00+00:00",
          "image_url": "https://example.com/bins.jpg",
          "created_at": "2026-09-18T10:15:30.123456+00:00",
          "updated_at": "2026-09-19T01:02:03+00:00",
          "assignedProfile": {"id": "22222222-2222-2222-2222-222222222222", "full_name": "Mum", "avatar_url": null},
          "createdProfile": null,
          "attachments": [{
            "id": "44444444-4444-4444-4444-444444444444",
            "chore_id": "11111111-1111-1111-1111-111111111111",
            "storage_path": "u/1-abc-bins.jpg",
            "public_url": "https://example.com/bins.jpg",
            "file_name": null, "mime_type": "image/jpeg", "sort_order": 0,
            "created_by": null, "created_at": "2026-09-18T10:16:00+00:00"
          }]
        }]
        """
        let chores = try decode([Chore].self, json)

        #expect(chores.count == 1)
        let chore = try #require(chores.first)
        #expect(chore.title == "Take out bins")
        #expect(chore.description == nil)
        #expect(chore.status == .inProgress)
        #expect(chore.dueDate != nil)
        #expect(chore.assignedProfile?.fullName == "Mum")
        #expect(chore.createdProfile == nil)
        #expect(chore.attachments?.count == 1)
        #expect(chore.attachments?.first?.fileName == nil)
    }

    @Test func choreDecodesWithMinimalFieldsAndNoEmbeds() throws {
        let json = """
        {"id": "11111111-1111-1111-1111-111111111111", "title": "T", "description": null,
         "assigned_to": null, "created_by": null, "status": "pending", "due_date": null,
         "image_url": null, "created_at": "2026-09-18T10:15:30+00:00", "updated_at": "2026-09-18T10:15:30+00:00"}
        """
        let chore = try decode(Chore.self, json)
        #expect(chore.dueDate == nil)
        #expect(chore.attachments == nil)
    }

    @Test func profileToleratesNullPersonalisation() throws {
        let json = #"{"id": "22222222-2222-2222-2222-222222222222", "full_name": "Dad", "avatar_url": null, "personalisation": null}"#
        let profile = try decode(Profile.self, json)
        #expect(profile.personalisation.theme == nil)
    }

    @Test func profileReadsTheme() throws {
        let json = ##"{"id": "22222222-2222-2222-2222-222222222222", "full_name": "Dad", "avatar_url": "https://example.com/a.png", "personalisation": {"theme": "#336699"}}"##
        let profile = try decode(Profile.self, json)
        #expect(profile.personalisation.theme == "#336699")
        #expect(profile.avatarURL?.host == "example.com")
    }

    @Test func commentDecodes() throws {
        let json = """
        {"id": "55555555-5555-5555-5555-555555555555", "chore_id": "11111111-1111-1111-1111-111111111111",
         "author_id": null, "body": "Done!", "created_at": "2026-09-19T00:00:00.5+00:00"}
        """
        let comment = try decode(ChoreComment.self, json)
        #expect(comment.body == "Done!")
        #expect(comment.authorId == nil)
    }
}
