import Foundation
import Testing
@testable import PapaTodos

struct ChoreSearchTests {
    private func chore(title: String, description: String?, status: ChoreStatus = .pending) -> Chore {
        let now = Date()
        return Chore(
            id: UUID(), title: title, description: description,
            assignedTo: nil, createdBy: nil, status: status, dueDate: nil,
            imageURL: nil, createdAt: now, updatedAt: now
        )
    }

    @Test func emptyQueryMatchesEverything() {
        let chore = chore(title: "Vacuum", description: nil)
        #expect(ChoreSearch.matches(chore, query: "", assignedName: nil, createdName: nil))
        #expect(ChoreSearch.matches(chore, query: "   ", assignedName: nil, createdName: nil))
    }

    @Test func matchesTitleCaseInsensitively() {
        let chore = chore(title: "Vacuum Lounge Room", description: nil)
        #expect(ChoreSearch.matches(chore, query: "vacuum", assignedName: nil, createdName: nil))
        #expect(ChoreSearch.matches(chore, query: "LOUNGE", assignedName: nil, createdName: nil))
        #expect(!ChoreSearch.matches(chore, query: "kitchen", assignedName: nil, createdName: nil))
    }

    @Test func matchesDescription() {
        let chore = chore(title: "Chore", description: "Don't forget the cobwebs in the corners.")
        #expect(ChoreSearch.matches(chore, query: "cobwebs", assignedName: nil, createdName: nil))
    }

    @Test func matchesAssigneeAndCreatorNames() {
        let chore = chore(title: "Chore", description: nil)
        #expect(ChoreSearch.matches(chore, query: "nando", assignedName: "Nando", createdName: nil))
        #expect(ChoreSearch.matches(chore, query: "mum", assignedName: nil, createdName: "Mum"))
    }

    @Test func matchesHumanReadableStatus() {
        let chore = chore(title: "Chore", description: nil, status: .inProgress)
        #expect(ChoreSearch.matches(chore, query: "in progress", assignedName: nil, createdName: nil))
        #expect(ChoreSearch.statusLabel(for: .inProgress) == "In progress")
        #expect(ChoreSearch.statusLabel(for: .done) == "Done")
        #expect(ChoreSearch.statusLabel(for: .pending) == "Pending")
    }
}
