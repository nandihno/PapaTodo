import Foundation

/// Fixed identities and a realistic chore set shared by previews, UI tests and unit
/// tests, so "Mine" has something to show. Never touches the network.
nonisolated enum FixtureData {
    static let currentUserID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    static let otherUserID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    static let profiles: [Profile] = [
        Profile(id: currentUserID, fullName: "Family Tester", avatarURL: nil, personalisation: .init()),
        Profile(id: otherUserID, fullName: "Alex Sample", avatarURL: nil, personalisation: .init(theme: "#4F46E5")),
    ]

    private static var currentSummary: ProfileSummary {
        ProfileSummary(id: currentUserID, fullName: "Family Tester", avatarURL: nil)
    }
    private static var otherSummary: ProfileSummary {
        ProfileSummary(id: otherUserID, fullName: "Alex Sample", avatarURL: nil)
    }

    /// Spans every sort bucket and tab: overdue, due today (date-only and timed),
    /// future, no due date, done; two are mine, three are Alex's.
    static func chores(now: Date = Date(), calendar: Calendar = .current) -> [Chore] {
        func day(_ offset: Int) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!
            return DueDateRule.dateOnlyTimestamp(
                year: calendar.component(.year, from: date),
                month: calendar.component(.month, from: date),
                day: calendar.component(.day, from: date),
                calendar: calendar
            )!
        }
        func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }
        let photo = URL(string: "https://fixtures.invalid/photo.jpg")

        func attachment(_ choreID: UUID, _ order: Int) -> ChoreAttachment {
            ChoreAttachment(
                id: UUID(), choreId: choreID, storagePath: "fixture/\(order)", publicURL: photo!,
                fileName: nil, mimeType: "image/jpeg", sortOrder: order, createdBy: nil, createdAt: ago(1)
            )
        }

        let recycling = UUID()
        let vacuum = UUID()
        return [
            Chore(id: recycling, title: "Take out recycling", description: "Bins go out Tuesday night.",
                  assignedTo: currentUserID, createdBy: otherUserID, status: .pending, dueDate: day(-2),
                  imageURL: nil, createdAt: ago(5), updatedAt: ago(5),
                  assignedProfile: currentSummary, createdProfile: otherSummary,
                  attachments: [attachment(recycling, 0), attachment(recycling, 1), attachment(recycling, 2)]),
            Chore(id: vacuum, title: "Vacuum lounge room", description: nil,
                  assignedTo: otherUserID, createdBy: currentUserID, status: .inProgress, dueDate: day(0),
                  imageURL: nil, createdAt: ago(1), updatedAt: ago(1),
                  assignedProfile: otherSummary, createdProfile: currentSummary),
            Chore(id: UUID(), title: "Water the garden", description: nil,
                  assignedTo: currentUserID, createdBy: currentUserID, status: .pending, dueDate: day(3),
                  imageURL: photo, createdAt: ago(3), updatedAt: ago(3),
                  assignedProfile: currentSummary, createdProfile: currentSummary),
            Chore(id: UUID(), title: "Sort the pantry", description: nil,
                  assignedTo: nil, createdBy: otherUserID, status: .pending, dueDate: nil,
                  imageURL: nil, createdAt: ago(4), updatedAt: ago(4),
                  assignedProfile: nil, createdProfile: otherSummary),
            Chore(id: UUID(), title: "Fold laundry", description: nil,
                  assignedTo: otherUserID, createdBy: otherUserID, status: .done, dueDate: day(-1),
                  imageURL: nil, createdAt: ago(2), updatedAt: ago(1),
                  assignedProfile: otherSummary, createdProfile: otherSummary),
        ]
    }
}
