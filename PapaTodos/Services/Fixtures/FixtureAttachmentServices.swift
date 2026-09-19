import Foundation

/// In-memory `chore_attachments` table with the same rules the live table enforces:
/// only the chore's creator or assignee may insert or delete rows.
actor FixtureAttachmentRepository: AttachmentRepository {
    struct Row: Equatable, Sendable {
        var id: UUID
        var choreID: UUID
        var attachment: NewAttachment
        var createdBy: UUID
    }

    private(set) var rows: [Row] = []
    private let currentUserID: UUID
    private let faults: FaultInjector
    private let chores: FixtureChoreRepository?

    init(currentUserID: UUID = FixtureData.currentUserID, faults: FaultInjector = FaultInjector(), chores: FixtureChoreRepository? = nil) {
        self.currentUserID = currentUserID
        self.faults = faults
        self.chores = chores
    }

    func insert(_ attachments: [NewAttachment], choreID: UUID) async throws -> [UUID] {
        try await faults.check(.insertAttachments)
        try await requireMembership(of: choreID)
        let new = attachments.map { Row(id: UUID(), choreID: choreID, attachment: $0, createdBy: currentUserID) }
        rows += new
        return new.map(\.id)
    }

    func delete(ids: [UUID]) async throws {
        try await faults.check(.deleteAttachments)
        let targets = rows.filter { ids.contains($0.id) }
        for choreID in Set(targets.map(\.choreID)) { try await requireMembership(of: choreID) }
        rows.removeAll { ids.contains($0.id) }
    }

    func rows(for choreID: UUID) -> [Row] { rows.filter { $0.choreID == choreID } }

    private func requireMembership(of choreID: UUID) async throws {
        guard let chores, let chore = try await chores.fetchChore(id: choreID) else { return }
        guard chore.createdBy == currentUserID || chore.assignedTo == currentUserID else {
            throw DataServiceError.notPermitted
        }
    }
}

/// In-memory `chore-images` bucket. `allowsDelete` defaults to **false** because the live
/// bucket currently has no DELETE policy, so removals are silently refused.
actor FixtureAttachmentStorage: AttachmentStorage {
    private(set) var objectPaths: Set<String> = []
    private let currentUserID: UUID
    private let faults: FaultInjector
    private let allowsDelete: Bool
    private var counter = 0

    init(currentUserID: UUID = FixtureData.currentUserID, faults: FaultInjector = FaultInjector(), allowsDelete: Bool = true) {
        self.currentUserID = currentUserID
        self.faults = faults
        self.allowsDelete = allowsDelete
    }

    func upload(_ photo: PhotoUpload) async throws -> UploadedFile {
        try await faults.checkUpload()
        counter += 1
        let path = "\(currentUserID.uuidString.lowercased())/fixture-\(counter)-\(photo.fileName)"
        objectPaths.insert(path)
        return UploadedFile(
            storagePath: path,
            publicURL: URL(string: "https://fixtures.invalid/storage/v1/object/public/chore-images/\(path)")!,
            fileName: photo.fileName, mimeType: photo.mimeType
        )
    }

    func remove(paths: [String]) async throws -> [String] {
        try await faults.check(.removeFiles)
        guard allowsDelete else { return [] }
        let removed = paths.filter { objectPaths.remove($0) != nil }
        return removed
    }
}
