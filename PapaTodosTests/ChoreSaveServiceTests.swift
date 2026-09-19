import Foundation
import Testing
@testable import PapaTodos

@MainActor
struct ChoreSaveServiceTests {
    let me = FixtureData.currentUserID
    let other = FixtureData.otherUserID

    struct World {
        let faults: FaultInjector
        let chores: FixtureChoreRepository
        let rows: FixtureAttachmentRepository
        let storage: FixtureAttachmentStorage
        let service: ChoreSaveService
    }

    private func makeWorld(chores seed: [Chore] = [], storageAllowsDelete: Bool = true) -> World {
        let faults = FaultInjector()
        let chores = FixtureChoreRepository(chores: seed, faults: faults)
        let rows = FixtureAttachmentRepository(faults: faults, chores: chores)
        let storage = FixtureAttachmentStorage(faults: faults, allowsDelete: storageAllowsDelete)
        return World(
            faults: faults, chores: chores, rows: rows, storage: storage,
            service: ChoreSaveService(chores: chores, attachments: rows, storage: storage)
        )
    }

    private func photo(_ name: String) -> PhotoUpload {
        PhotoUpload(data: Data(name.utf8), fileName: "\(name).jpg", mimeType: "image/jpeg")
    }

    private func draft(_ title: String = "New chore") -> ChoreDraft {
        ChoreDraft(title: title, description: nil, assignedTo: nil, status: .pending, dueDate: nil)
    }

    private func existingChore(createdBy: UUID? = nil, assignedTo: UUID? = nil, imageURL: URL? = nil) -> Chore {
        Chore(
            id: UUID(), title: "Existing", description: "keep me", assignedTo: assignedTo, createdBy: createdBy ?? me,
            status: .pending, dueDate: Date(timeIntervalSince1970: 1_800_000_000), imageURL: imageURL,
            createdAt: Date(), updatedAt: Date()
        )
    }

    /// A pre-existing attachment: a real row and a real object, as if uploaded earlier.
    private func seedAttachment(_ world: World, on chore: Chore, order: Int = 0) async throws -> ChoreAttachment {
        let file = try await world.storage.upload(photo("seed\(order)"))
        let ids = try await world.rows.insert(
            [NewAttachment(storagePath: file.storagePath, publicURL: file.publicURL, fileName: file.fileName, mimeType: file.mimeType, sortOrder: order)],
            choreID: chore.id
        )
        return ChoreAttachment(
            id: ids[0], choreId: chore.id, storagePath: file.storagePath, publicURL: file.publicURL,
            fileName: file.fileName, mimeType: file.mimeType, sortOrder: order, createdBy: me, createdAt: Date()
        )
    }

    // MARK: create

    @Test func createWithPhotosStoresChoreRowsAndObjectsInOrder() async throws {
        let world = makeWorld()
        let request = ChoreSaveService.Request(kind: .create(draft("With photos")), newPhotos: [photo("a"), photo("b")])

        let success = try await world.service.save(request).get()

        #expect(success.warnings.isEmpty)
        let chore = try #require(await world.chores.allChores.first)
        #expect(chore.createdBy == me)
        let rows = await world.rows.rows(for: chore.id)
        #expect(rows.map(\.attachment.sortOrder) == [0, 1])
        #expect(rows.allSatisfy { $0.createdBy == me })
        #expect(chore.imageURL == rows.first?.attachment.publicURL)
        #expect(await world.storage.objectPaths.count == 2)
    }

    @Test func secondUploadFailingRemovesTheFirstAndCreatesNothing() async {
        let world = makeWorld()
        await world.faults.arm(.upload(nth: 2))

        let result = await world.service.save(.init(kind: .create(draft()), newPhotos: [photo("a"), photo("b")]))

        guard case .failure(let failure) = result else { Issue.record("expected failure"); return }
        #expect(failure.orphanedPaths.isEmpty)
        #expect(await world.storage.objectPaths.isEmpty)
        #expect(await world.chores.allChores.isEmpty)
        #expect(await world.rows.rows.isEmpty)
    }

    @Test func choreCreationFailingRemovesEveryUpload() async {
        let world = makeWorld()
        await world.faults.arm(.createChore, error: .offline)

        let result = await world.service.save(.init(kind: .create(draft()), newPhotos: [photo("a"), photo("b")]))

        guard case .failure(let failure) = result else { Issue.record("expected failure"); return }
        #expect(failure.error == .offline)
        #expect(await world.storage.objectPaths.isEmpty)
        #expect(await world.chores.allChores.isEmpty)
    }

    @Test func attachmentRowFailureRollsBackTheChoreAndTheUploads() async {
        let world = makeWorld()
        await world.faults.arm(.insertAttachments, error: .notPermitted)

        let result = await world.service.save(.init(kind: .create(draft()), newPhotos: [photo("a")]))

        guard case .failure(let failure) = result else { Issue.record("expected failure"); return }
        #expect(failure.error == .notPermitted)
        #expect(failure.orphanedChoreID == nil)
        #expect(await world.chores.allChores.isEmpty)
        #expect(await world.rows.rows.isEmpty)
        #expect(await world.storage.objectPaths.isEmpty)
    }

    @Test func aChoreThatCannotBeRolledBackIsReportedNotHidden() async {
        let world = makeWorld()
        await world.faults.arm(.insertAttachments)
        await world.faults.arm(.deleteChore)

        let result = await world.service.save(.init(kind: .create(draft()), newPhotos: [photo("a")]))

        guard case .failure(let failure) = result else { Issue.record("expected failure"); return }
        let leftover = await world.chores.allChores
        #expect(leftover.count == 1)
        #expect(failure.orphanedChoreID == leftover.first?.id)
    }

    @Test func uploadsThatCannotBeRemovedAreReportedAsOrphans() async {
        // The live bucket currently refuses deletes, so cleanup cannot succeed there.
        let world = makeWorld(storageAllowsDelete: false)
        await world.faults.arm(.createChore)

        let result = await world.service.save(.init(kind: .create(draft()), newPhotos: [photo("a"), photo("b")]))

        guard case .failure(let failure) = result else { Issue.record("expected failure"); return }
        let inBucket = await world.storage.objectPaths
        #expect(inBucket.count == 2)
        #expect(Set(failure.orphanedPaths) == inBucket)
    }

    @Test func createWithoutPhotosTouchesNoStorage() async throws {
        let world = makeWorld()
        _ = try await world.service.save(.init(kind: .create(draft()))).get()
        #expect(await world.storage.objectPaths.isEmpty)
        #expect(await world.rows.rows.isEmpty)
        #expect(await world.chores.allChores.first?.imageURL == nil)
    }

    // MARK: edit

    @Test func editAddingPhotosAppendsAfterExistingOnesAndKeepsThePrimaryImage() async throws {
        let world = makeWorld()
        var chore = existingChore()
        let seeded = try await seedAttachment(world, on: chore)
        chore.imageURL = seeded.publicURL
        await world.chores.store(chore)

        let success = try await world.service.save(.init(
            kind: .edit(original: chore, patch: ChorePatch(title: "Renamed")), keep: [seeded], newPhotos: [photo("new")]
        )).get()

        let rows = await world.rows.rows(for: chore.id).sorted { $0.attachment.sortOrder < $1.attachment.sortOrder }
        #expect(rows.map(\.attachment.sortOrder) == [0, 1])
        #expect(success.chore.title == "Renamed")
        #expect(success.chore.imageURL == seeded.publicURL)
    }

    @Test func editWithNoExistingPhotosMakesTheFirstNewPhotoThePrimaryImage() async throws {
        let world = makeWorld()
        let chore = existingChore()
        await world.chores.store(chore)

        let success = try await world.service.save(.init(kind: .edit(original: chore, patch: ChorePatch()), newPhotos: [photo("new")])).get()

        let row = try #require(await world.rows.rows(for: chore.id).first)
        #expect(success.chore.imageURL == row.attachment.publicURL)
    }

    @Test func failedUpdateRollsBackNewRowsAndUploadsButNeverTouchesExistingPhotos() async throws {
        let world = makeWorld()
        let chore = existingChore()
        await world.chores.store(chore)
        let seeded = try await seedAttachment(world, on: chore)
        await world.faults.arm(.updateChore, error: .offline)

        let result = await world.service.save(.init(
            kind: .edit(original: chore, patch: ChorePatch(title: "x")), keep: [seeded], newPhotos: [photo("new")]
        ))

        guard case .failure(let failure) = result else { Issue.record("expected failure"); return }
        #expect(failure.error == .offline)
        let rows = await world.rows.rows(for: chore.id)
        #expect(rows.map(\.id) == [seeded.id])
        #expect(await world.storage.objectPaths == [seeded.storagePath])
        #expect(await world.chores.allChores.first?.title == "Existing")
    }

    @Test func failedRowInsertOnEditLeavesTheChoreUntouchedAndCleansUploads() async throws {
        let world = makeWorld()
        let chore = existingChore()
        await world.chores.store(chore)
        await world.faults.arm(.insertAttachments)

        let result = await world.service.save(.init(kind: .edit(original: chore, patch: ChorePatch(title: "changed")), newPhotos: [photo("new")]))

        guard case .failure = result else { Issue.record("expected failure"); return }
        #expect(await world.chores.allChores.first?.title == "Existing")
        #expect(await world.storage.objectPaths.isEmpty)
    }

    @Test func removingAPhotoDeletesItsRowAndFileAndMovesThePrimaryImage() async throws {
        let world = makeWorld()
        var chore = existingChore()
        let first = try await seedAttachment(world, on: chore, order: 0)
        let second = try await seedAttachment(world, on: chore, order: 1)
        chore.imageURL = first.publicURL
        await world.chores.store(chore)

        let success = try await world.service.save(.init(
            kind: .edit(original: chore, patch: ChorePatch()), keep: [second], remove: [first]
        )).get()

        #expect(success.warnings.isEmpty)
        #expect(await world.rows.rows(for: chore.id).map(\.id) == [second.id])
        #expect(await world.storage.objectPaths == [second.storagePath])
        #expect(success.chore.imageURL == second.publicURL)
    }

    @Test func removingTheLastPhotoClearsTheLegacyImageURL() async throws {
        let world = makeWorld()
        var chore = existingChore()
        let only = try await seedAttachment(world, on: chore)
        chore.imageURL = only.publicURL
        await world.chores.store(chore)

        let success = try await world.service.save(.init(kind: .edit(original: chore, patch: ChorePatch()), remove: [only])).get()
        #expect(success.chore.imageURL == nil)
    }

    @Test func removingALegacyImageNeedsNoRowDelete() async throws {
        let world = makeWorld()
        let file = try await world.storage.upload(photo("legacy"))
        var chore = existingChore(imageURL: file.publicURL)
        chore.imageURL = file.publicURL
        await world.chores.store(chore)
        let legacy = try #require(ChoreAttachments.all(for: chore).first)
        #expect(legacy.storagePath == file.storagePath)

        let success = try await world.service.save(.init(kind: .edit(original: chore, patch: ChorePatch()), remove: [legacy])).get()

        #expect(success.chore.imageURL == nil)
        #expect(await world.storage.objectPaths.isEmpty)
    }

    @Test func rowDeleteFailureKeepsTheFilesAndWarns() async throws {
        let world = makeWorld()
        let chore = existingChore()
        await world.chores.store(chore)
        let seeded = try await seedAttachment(world, on: chore)
        await world.faults.arm(.deleteAttachments, error: .notPermitted)

        let success = try await world.service.save(.init(kind: .edit(original: chore, patch: ChorePatch(title: "ok")), remove: [seeded])).get()

        #expect(success.warnings == [.removedPhotosNotDeleted(.notPermitted)])
        #expect(await world.rows.rows(for: chore.id).count == 1)
        #expect(await world.storage.objectPaths == [seeded.storagePath])   // rows still point at it
    }

    @Test func storageThatRefusesDeletesIsReportedAndRetryable() async throws {
        let world = makeWorld(storageAllowsDelete: false)
        let chore = existingChore()
        await world.chores.store(chore)
        let seeded = try await seedAttachment(world, on: chore)

        let success = try await world.service.save(.init(kind: .edit(original: chore, patch: ChorePatch()), remove: [seeded])).get()

        #expect(success.warnings == [.storageCleanupIncomplete(paths: [seeded.storagePath])])
        let leftover = await world.service.removeFiles(paths: [seeded.storagePath])
        #expect(leftover == [seeded.storagePath])   // still refused: retry reports it again, no crash
    }

    @Test func editingSomeoneElsesChoreCannotAddPhotosAndChangesNothing() async {
        let world = makeWorld()
        let theirs = existingChore(createdBy: other, assignedTo: other)
        await world.chores.store(theirs)

        let result = await world.service.save(.init(kind: .edit(original: theirs, patch: ChorePatch(title: "hijack")), newPhotos: [photo("x")]))

        guard case .failure(let failure) = result else { Issue.record("expected failure"); return }
        #expect(failure.error == .notPermitted)
        #expect(await world.chores.allChores.first?.title == "Existing")
        #expect(await world.storage.objectPaths.isEmpty)
    }

    @Test func textOnlyEditsMakeNoAttachmentOrStorageCalls() async throws {
        let world = makeWorld()
        let chore = existingChore()
        await world.chores.store(chore)
        await world.faults.arm(.insertAttachments)
        await world.faults.arm(.deleteAttachments)
        await world.faults.arm(.removeFiles)

        let success = try await world.service.save(.init(kind: .edit(original: chore, patch: ChorePatch(title: "Only text")))).get()
        #expect(success.chore.title == "Only text")
        #expect(success.warnings.isEmpty)   // armed faults never fired
    }

    // MARK: patch semantics

    @Test func aPatchOnlyChangesTheFieldsItNames() async throws {
        let world = makeWorld()
        let chore = existingChore()
        await world.chores.store(chore)

        let updated = try await world.chores.update(id: chore.id, patch: ChorePatch(title: "New"))

        #expect(updated.title == "New")
        #expect(updated.description == "keep me")
        #expect(updated.dueDate == chore.dueDate)
        #expect(updated.createdBy == chore.createdBy)
    }

    @Test func aPatchCanExplicitlyClearAField() async throws {
        let world = makeWorld()
        let chore = existingChore()
        await world.chores.store(chore)
        let updated = try await world.chores.update(id: chore.id, patch: ChorePatch(description: .some(nil), dueDate: .some(nil)))
        #expect(updated.description == nil)
        #expect(updated.dueDate == nil)
    }

    // MARK: delete

    @Test func deletingAChoreRemovesItsPhotoFiles() async throws {
        let world = makeWorld()
        var chore = existingChore()
        let seeded = try await seedAttachment(world, on: chore)
        chore.attachments = [seeded]
        await world.chores.store(chore)

        let outcome = try await ChoreDeleteService(chores: world.chores, storage: world.storage).delete(chore).get()

        #expect(outcome.leftoverPaths.isEmpty)
        #expect(await world.chores.allChores.isEmpty)
        #expect(await world.storage.objectPaths.isEmpty)
    }

    @Test func deleteReportsFilesTheBucketRefusedToRemove() async throws {
        let world = makeWorld(storageAllowsDelete: false)
        var chore = existingChore()
        let seeded = try await seedAttachment(world, on: chore)
        chore.attachments = [seeded]
        await world.chores.store(chore)

        let outcome = try await ChoreDeleteService(chores: world.chores, storage: world.storage).delete(chore).get()
        #expect(outcome.leftoverPaths == [seeded.storagePath])
        #expect(await world.chores.allChores.isEmpty)
    }

    @Test func aFailedChoreDeleteRemovesNoFiles() async throws {
        let world = makeWorld()
        var chore = existingChore()
        let seeded = try await seedAttachment(world, on: chore)
        chore.attachments = [seeded]
        await world.chores.store(chore)
        await world.faults.arm(.deleteChore, error: .offline)

        let result = await ChoreDeleteService(chores: world.chores, storage: world.storage).delete(chore)

        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(error == .offline)
        #expect(await world.chores.allChores.count == 1)
        #expect(await world.storage.objectPaths == [seeded.storagePath])
    }
}
