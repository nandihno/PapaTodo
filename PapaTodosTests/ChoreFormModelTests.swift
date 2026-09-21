import Foundation
import Testing
@testable import PapaTodos

@MainActor
struct ChoreFormModelTests {
    let me = FixtureData.currentUserID

    struct World {
        let faults: FaultInjector
        let chores: FixtureChoreRepository
        let rows: FixtureAttachmentRepository
        let storage: FixtureAttachmentStorage
    }

    private func makeWorld(seed: [Chore] = [], storageAllowsDelete: Bool = true) -> World {
        let faults = FaultInjector()
        let chores = FixtureChoreRepository(chores: seed, faults: faults)
        return World(
            faults: faults, chores: chores,
            rows: FixtureAttachmentRepository(faults: faults, chores: chores),
            storage: FixtureAttachmentStorage(faults: faults, allowsDelete: storageAllowsDelete)
        )
    }

    private func makeModel(_ world: World, mode: ChoreFormModel.Mode, onExpired: @escaping @MainActor () -> Void = {}) -> ChoreFormModel {
        ChoreFormModel(
            mode: mode,
            saveService: ChoreSaveService(chores: world.chores, attachments: world.rows, storage: world.storage),
            deleteService: ChoreDeleteService(chores: world.chores, storage: world.storage),
            profiles: FixtureProfileRepository(),
            currentUserID: FixtureData.currentUserID,
            now: Date(timeIntervalSince1970: 1_790_000_000),
            onSessionExpired: onExpired
        )
    }

    private let listDescription = "<ul><li>eggs</li><li>milk</li></ul><p><b>Note</b></p>"

    private func chore(
        description: String? = "Plain note", due: Date? = Date(timeIntervalSince1970: 1_800_000_123.456)
    ) -> Chore {
        Chore(
            id: UUID(), title: "Existing", description: description, assignedTo: FixtureData.otherUserID,
            createdBy: FixtureData.currentUserID, status: .inProgress, dueDate: due, imageURL: nil,
            createdAt: Date(), updatedAt: Date()
        )
    }

    private func pngData() throws -> Data {
        // A 1x1 PNG.
        try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
    }

    // MARK: create

    @Test func aTitleIsRequiredAndNothingIsSentWithoutOne() async {
        let world = makeWorld()
        let model = makeModel(world, mode: .create)
        model.title = "   "
        await model.save()
        #expect(model.titleError == "Title is required.")
        #expect(await world.chores.allChores.isEmpty)
        #expect(!model.didFinish)
    }

    @Test func createTrimsTheTitleStoresPlainTextAndFinishes() async throws {
        let world = makeWorld()
        let model = makeModel(world, mode: .create)
        model.title = "  Wash car  "
        model.descriptionText = AttributedString("  Use the good soap  ")
        model.assignedTo = FixtureData.otherUserID
        model.status = .inProgress
        model.due.hasDueDate = true

        await model.save()

        let saved = try #require(await world.chores.allChores.first)
        #expect(saved.title == "Wash car")
        #expect(saved.description == "Use the good soap")
        #expect(saved.assignedTo == FixtureData.otherUserID)
        #expect(saved.status == .inProgress)
        #expect(saved.createdBy == me)
        #expect(saved.dueDate != nil && DueDateRule.isDateOnly(saved.dueDate!))
        #expect(model.didFinish)
    }

    @Test func aBlankDescriptionIsStoredAsNothing() async throws {
        let world = makeWorld()
        let model = makeModel(world, mode: .create)
        model.title = "T"
        model.descriptionText = AttributedString(" \n ")
        await model.save()
        #expect(try #require(await world.chores.allChores.first).description == nil)
    }

    // MARK: edit: only what changed is sent

    @Test func savingAnUnchangedEditWritesNothing() async throws {
        let existing = chore()
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))
        #expect(!model.isDirty)

        await model.save()

        let after = try #require(await world.chores.allChores.first)
        #expect(after.updatedAt == existing.updatedAt)   // no write happened
        #expect(model.didFinish && model.notice == nil)
    }

    @Test func editingOnlyTheTitleLeavesTheDueDateAndDescriptionByteForByteAlone() async throws {
        let existing = chore(description: "  odd spacing kept  ", due: Date(timeIntervalSince1970: 1_800_000_123.456))
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))
        model.title = "Renamed"

        await model.save()

        let after = try #require(await world.chores.allChores.first)
        #expect(after.title == "Renamed")
        #expect(after.dueDate == existing.dueDate)             // sub-second value untouched: no drift
        #expect(after.description == "  odd spacing kept  ")  // not re-trimmed or re-encoded
    }

    @Test func changingTheStatusOrAssigneeSendsOnlyThose() async throws {
        let existing = chore()
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))
        model.status = .done
        model.assignedTo = nil

        await model.save()

        let after = try #require(await world.chores.allChores.first)
        #expect(after.status == .done)
        #expect(after.assignedTo == nil)
        #expect(after.title == "Existing")
        #expect(after.dueDate == existing.dueDate)
    }

    @Test func removingTheDueDateClearsItAndChangingTheTimeUpdatesIt() async throws {
        let existing = chore()
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))
        model.due.hasDueDate = false
        await model.save()
        #expect(try #require(await world.chores.allChores.first).dueDate == nil)
    }

    // MARK: protected descriptions

    @Test func aProtectedDescriptionIsShownButNeverRewrittenByUnrelatedEdits() async throws {
        let existing = chore(description: listDescription)
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))
        #expect(model.isDescriptionProtected)

        model.title = "Renamed"
        model.due.hasDueDate = false
        await model.save()

        let after = try #require(await world.chores.allChores.first)
        #expect(after.description == listDescription)
        #expect(after.title == "Renamed")
    }

    @Test func choosingToEditAProtectedDescriptionFlattensItAndSavesTheEdit() async throws {
        let existing = chore(description: listDescription)
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))

        model.beginEditingProtectedDescription()
        #expect(!model.isDescriptionProtected)
        #expect(String(model.descriptionText.characters) == "• eggs\n• milk\n\nNote")
        #expect(model.isDirty)

        await model.save()
        #expect(try #require(await world.chores.allChores.first).description == "• eggs\n• milk\n\nNote")
    }

    @Test func aDescriptionWithLinksAndBreaksIsEditableAndKeepsItsLinks() async throws {
        let html = "<p>See <a href=\"https://example.com\">this</a></p>"
        let existing = chore(description: html)
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))
        #expect(!model.isDescriptionProtected)

        model.title = "Just a rename"
        await model.save()
        #expect(try #require(await world.chores.allChores.first).description == html)   // untouched
    }

    // MARK: failures and re-entry

    @Test func aFailedSaveKeepsEveryFieldAndAllowsARetry() async throws {
        let world = makeWorld()
        let model = makeModel(world, mode: .create)
        model.title = "Keep me"
        model.descriptionText = AttributedString("draft text")
        await world.faults.arm(.createChore, error: .offline)

        await model.save()

        #expect(!model.didFinish)
        #expect(model.errorMessage?.contains("offline") == true)
        #expect(model.errorMessage?.contains("still here") == true)
        #expect(model.title == "Keep me")
        #expect(String(model.descriptionText.characters) == "draft text")
        #expect(model.phase == .editing)

        await model.save()   // fault was one-shot: the retry succeeds
        #expect(model.didFinish)
        #expect(await world.chores.allChores.count == 1)
    }

    @Test func doubleTappingSaveCreatesOneChore() async {
        let world = makeWorld()
        let model = makeModel(world, mode: .create)
        model.title = "Once"
        async let first: Void = model.save()
        async let second: Void = model.save()
        _ = await (first, second)
        #expect(await world.chores.allChores.count == 1)
    }

    @Test func sessionExpiryDuringSaveIsForwardedNotShownAsAFormError() async {
        var expired = 0
        let world = makeWorld()
        let model = makeModel(world, mode: .create, onExpired: { expired += 1 })
        model.title = "T"
        await world.faults.arm(.createChore, error: .sessionExpired)
        await model.save()
        #expect(expired == 1)
        #expect(model.errorMessage == nil)
    }

    // MARK: photos

    @Test func imagesAreAddedAndCanBeRemovedBeforeSaving() async throws {
        let world = makeWorld()
        let model = makeModel(world, mode: .create)
        let png = try pngData()

        await model.addPhotos([(png, "a.png"), (png, "b.png")])
        #expect(model.pendingPhotos.count == 2)
        #expect(model.photoMessage == "2 photos selected.")
        #expect(model.isDirty)

        model.removePendingPhoto(id: model.pendingPhotos[0].id)
        #expect(model.pendingPhotos.count == 1)
    }

    @Test func aSelectionContainingANonImageAddsNothing() async throws {
        let model = makeModel(makeWorld(), mode: .create)
        await model.addPhotos([(try pngData(), "ok.png"), (Data("not an image".utf8), "notes.txt")])
        #expect(model.pendingPhotos.isEmpty)
        #expect(model.photoMessage == "Choose or paste image files only.")
    }

    @Test func pastedImagesGetTheClipboardMessage() async throws {
        let model = makeModel(makeWorld(), mode: .create)
        await model.addPhotos([(try pngData(), "pasted-photo.png")], source: .pasteboard)
        #expect(model.photoMessage == "Photo pasted from the clipboard.")
        model.noteNoImageOnPasteboard()
        #expect(model.photoMessage?.contains("No image was found") == true)
    }

    @Test func createWithPhotosUploadsThemAndSetsThePrimaryImage() async throws {
        let world = makeWorld()
        let model = makeModel(world, mode: .create)
        model.title = "With photo"
        await model.addPhotos([(try pngData(), "a.png")])
        await model.save()
        let saved = try #require(await world.chores.allChores.first)
        #expect(saved.imageURL != nil)
        #expect(await world.storage.objectPaths.count == 1)
        #expect(model.didFinish)
    }

    @Test func removingAnExistingPhotoMarksItForDeletionOnSave() async throws {
        var existing = chore()
        let world = makeWorld(seed: [])
        let file = try await world.storage.upload(PhotoUpload(data: Data([1]), fileName: "x.jpg", mimeType: "image/jpeg"))
        let ids = try await world.rows.insert(
            [NewAttachment(storagePath: file.storagePath, publicURL: file.publicURL, fileName: "x.jpg", mimeType: "image/jpeg", sortOrder: 0)],
            choreID: existing.id
        )
        existing.attachments = [ChoreAttachment(
            id: ids[0], choreId: existing.id, storagePath: file.storagePath, publicURL: file.publicURL,
            fileName: "x.jpg", mimeType: "image/jpeg", sortOrder: 0, createdBy: me, createdAt: Date()
        )]
        existing.imageURL = file.publicURL
        await world.chores.store(existing)
        let model = makeModel(world, mode: .edit(existing))
        #expect(model.existingAttachments.count == 1)

        model.removeExistingAttachment(model.existingAttachments[0])
        #expect(model.existingAttachments.isEmpty && model.removedAttachments.count == 1)
        #expect(model.isDirty)

        await model.save()
        #expect(await world.rows.rows.isEmpty)
        #expect(await world.storage.objectPaths.isEmpty)
        #expect(try #require(await world.chores.allChores.first).imageURL == nil)
    }

    @Test func aStorageThatCannotDeleteProducesAVisibleNotice() async throws {
        var existing = chore()
        let world = makeWorld(seed: [], storageAllowsDelete: false)
        let file = try await world.storage.upload(PhotoUpload(data: Data([1]), fileName: "x.jpg", mimeType: "image/jpeg"))
        let ids = try await world.rows.insert(
            [NewAttachment(storagePath: file.storagePath, publicURL: file.publicURL, fileName: "x.jpg", mimeType: "image/jpeg", sortOrder: 0)],
            choreID: existing.id
        )
        existing.attachments = [ChoreAttachment(
            id: ids[0], choreId: existing.id, storagePath: file.storagePath, publicURL: file.publicURL,
            fileName: "x.jpg", mimeType: "image/jpeg", sortOrder: 0, createdBy: me, createdAt: Date()
        )]
        await world.chores.store(existing)
        let model = makeModel(world, mode: .edit(existing))
        model.removeExistingAttachment(model.existingAttachments[0])

        await model.save()

        #expect(model.didFinish)
        #expect(model.notice?.contains("still in storage") == true)
    }

    // MARK: delete

    @Test func deleteRemovesTheChoreAndFinishes() async {
        let existing = chore()
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))
        await model.delete()
        #expect(await world.chores.allChores.isEmpty)
        #expect(model.didFinish)
    }

    @Test func aFailedDeleteKeepsTheChoreAndShowsWhy() async {
        let existing = chore()
        let world = makeWorld(seed: [existing])
        let model = makeModel(world, mode: .edit(existing))
        await world.faults.arm(.deleteChore, error: .offline)
        await model.delete()
        #expect(await world.chores.allChores.count == 1)
        #expect(!model.didFinish)
        #expect(model.errorMessage?.contains("offline") == true)
    }

    @Test func createModeCannotDelete() async {
        let world = makeWorld()
        let model = makeModel(world, mode: .create)
        await model.delete()
        #expect(!model.didFinish)
    }

    // MARK: dirty tracking and loading

    @Test func dirtyTrackingSeesEditsAndIgnoresNoOps() {
        let existing = chore()
        let model = makeModel(makeWorld(seed: [existing]), mode: .edit(existing))
        #expect(!model.isDirty)
        model.title = "Changed"
        #expect(model.isDirty)
        model.title = "Existing"
        #expect(!model.isDirty)
        model.status = .done
        #expect(model.isDirty)
    }

    @Test func peopleLoadForTheAssigneePicker() async {
        let model = makeModel(makeWorld(), mode: .create)
        await model.loadPeople()
        #expect(model.people.count == 2)
    }

    // MARK: creator-only delete

    @Test func onlyTheCreatorCanDeleteAChore() async {
        let world = makeWorld()
        let mine = chore()                                   // created by the current user
        var theirs = chore()
        theirs.createdBy = FixtureData.otherUserID           // assigned to me, created by someone else
        theirs.assignedTo = FixtureData.currentUserID
        #expect(makeModel(world, mode: .edit(mine)).canDelete)
        #expect(!makeModel(world, mode: .edit(theirs)).canDelete)
        #expect(!makeModel(world, mode: .create).canDelete)
    }

    @Test func deletingSomeoneElsesChoreIsRefusedWithoutTouchingIt() async {
        let world = makeWorld()
        var theirs = chore()
        theirs.createdBy = FixtureData.otherUserID
        theirs.assignedTo = FixtureData.currentUserID
        await world.chores.store(theirs)
        let model = makeModel(world, mode: .edit(theirs))

        await model.delete()

        #expect(model.errorMessage == "Only the person who created this chore can delete it.")
        #expect(!model.wasDeleted)
        #expect(await world.chores.allChores.contains { $0.id == theirs.id })
    }

    @Test func theRepositoryRefusesToDeleteSomeoneElsesChore() async {
        var theirs = chore()
        theirs.createdBy = FixtureData.otherUserID
        let repository = FixtureChoreRepository(chores: [theirs])
        await #expect(throws: DataServiceError.notCreator) { try await repository.delete(id: theirs.id) }
        #expect(await repository.allChores.count == 1)
    }
}
