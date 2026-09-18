import Foundation
import Testing
@testable import PapaTodos

struct ChoreFilterTests {
    let currentUserID = UUID()
    let otherUserID = UUID()

    private func chore(status: ChoreStatus, assignedTo: UUID?) -> Chore {
        let now = Date()
        return Chore(
            id: UUID(), title: "Test chore", description: nil,
            assignedTo: assignedTo, createdBy: nil, status: status, dueDate: nil,
            imageURL: nil, createdAt: now, updatedAt: now
        )
    }

    @Test func mineTabShowsOnlyActiveChoresAssignedToCurrentUser() {
        let assignedToMe = chore(status: .pending, assignedTo: currentUserID)
        let assignedToOther = chore(status: .pending, assignedTo: otherUserID)
        let unassigned = chore(status: .pending, assignedTo: nil)
        let doneAssignedToMe = chore(status: .done, assignedTo: currentUserID)

        #expect(ChoreFilter.belongs(assignedToMe, in: .mine, currentUserID: currentUserID))
        #expect(!ChoreFilter.belongs(assignedToOther, in: .mine, currentUserID: currentUserID))
        #expect(!ChoreFilter.belongs(unassigned, in: .mine, currentUserID: currentUserID))
        #expect(!ChoreFilter.belongs(doneAssignedToMe, in: .mine, currentUserID: currentUserID))
    }

    @Test func allTabShowsEveryActiveChoreRegardlessOfAssignee() {
        let assignedToMe = chore(status: .pending, assignedTo: currentUserID)
        let assignedToOther = chore(status: .inProgress, assignedTo: otherUserID)
        let done = chore(status: .done, assignedTo: otherUserID)

        #expect(ChoreFilter.belongs(assignedToMe, in: .all, currentUserID: currentUserID))
        #expect(ChoreFilter.belongs(assignedToOther, in: .all, currentUserID: currentUserID))
        #expect(!ChoreFilter.belongs(done, in: .all, currentUserID: currentUserID))
    }

    @Test func doneTabShowsOnlyCompletedChores() {
        let done = chore(status: .done, assignedTo: currentUserID)
        let pending = chore(status: .pending, assignedTo: currentUserID)

        #expect(ChoreFilter.belongs(done, in: .done, currentUserID: currentUserID))
        #expect(!ChoreFilter.belongs(pending, in: .done, currentUserID: currentUserID))
    }
}
