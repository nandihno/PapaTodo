import Foundation
import Testing
@testable import PapaTodos

private func template(
    _ title: String, order: Int = 0, description: String? = nil, assignedTo: UUID? = nil, id: UUID = UUID()
) -> ChoreTemplate {
    ChoreTemplate(id: id, title: title, description: description, assignedTo: assignedTo, sortOrder: order, createdBy: nil)
}

private let listDescription = "<p>Check the list:</p><ul><li>Milk</li><li>Bread</li></ul>"

// MARK: rules

struct FavouriteRulesTests {
    @Test func suggestionsMatchAnywhereIgnoringCaseAndAccentsInSharedOrder() {
        let list = [template("Woolworths run", order: 0), template("Café pickup", order: 1), template("Put the bins out", order: 2)]
        #expect(FavouriteRules.suggestions(for: "RUN", in: list).map(\.title) == ["Woolworths run"])
        #expect(FavouriteRules.suggestions(for: "cafe", in: list).map(\.title) == ["Café pickup"])
        #expect(FavouriteRules.suggestions(for: "u", in: list).map(\.title) == ["Woolworths run", "Café pickup", "Put the bins out"])
    }

    @Test func noSuggestionsForBlankInputOrAnExactMatch() {
        let list = [template("Woolworths run")]
        #expect(FavouriteRules.suggestions(for: "  ", in: list).isEmpty)
        #expect(FavouriteRules.suggestions(for: " woolworths RUN ", in: list).isEmpty)
    }

    @Test func suggestionsAreCapped() {
        let list = (0..<6).map { template("Shop \($0)", order: $0) }
        #expect(FavouriteRules.suggestions(for: "shop", in: list).count == 3)
    }

    @Test func titleClashesIgnoreCaseAndSurroundingSpaces() {
        #expect(FavouriteRules.sameTitle("  Woolworths Run ", "woolworths run"))
        #expect(!FavouriteRules.sameTitle("Woolworths run", "Woolworths runs"))
    }

    @Test func aNewFavouriteGoesAfterTheLastOne() {
        #expect(FavouriteRules.nextSortOrder(after: []) == 0)
        #expect(FavouriteRules.nextSortOrder(after: [template("a", order: 4), template("b", order: 2)]) == 5)
    }

    @Test func movingMatchesListDragOffsets() {
        let items = ["a", "b", "c", "d"]
        // Drag "a" to the end, "d" to the top, "b" below "c", and two rows at once.
        #expect(FavouriteRules.moving(items, fromOffsets: [0], toOffset: 4) == ["b", "c", "d", "a"])
        #expect(FavouriteRules.moving(items, fromOffsets: [3], toOffset: 0) == ["d", "a", "b", "c"])
        #expect(FavouriteRules.moving(items, fromOffsets: [1], toOffset: 3) == ["a", "c", "b", "d"])
        #expect(FavouriteRules.moving(items, fromOffsets: [0, 2], toOffset: 4) == ["b", "d", "a", "c"])
        #expect(FavouriteRules.moving(items, fromOffsets: [2], toOffset: 2) == items)
    }

    @Test func reorderingReportsOnlyTheRowsThatMoved() {
        let a = template("a", order: 0), b = template("b", order: 1), c = template("c", order: 2)
        let result = FavouriteRules.reordered([b, a, c])
        #expect(result.list.map(\.sortOrder) == [0, 1, 2])
        #expect(result.changes == [b.id: 0, a.id: 1])
    }

    @Test func aDraftFromAChoreKeepsItsDescriptionExactly() {
        let chore = Chore(
            id: UUID(), title: "Woolworths run", description: listDescription, assignedTo: FixtureData.otherUserID,
            createdBy: nil, status: .done, dueDate: Date(), imageURL: nil, createdAt: Date(), updatedAt: Date()
        )
        #expect(ChoreTemplateDraft(chore: chore) == ChoreTemplateDraft(
            title: "Woolworths run", description: listDescription, assignedTo: FixtureData.otherUserID
        ))
    }
}

// MARK: applying a favourite to the chore form

@MainActor
struct ChoreFormFavouriteTests {
    private func makeModel(mode: ChoreFormModel.Mode = .create) -> (ChoreFormModel, FixtureChoreRepository) {
        let faults = FaultInjector()
        let chores = FixtureChoreRepository(chores: [], faults: faults)
        let model = ChoreFormModel(
            mode: mode,
            saveService: ChoreSaveService(
                chores: chores, attachments: FixtureAttachmentRepository(faults: faults, chores: chores),
                storage: FixtureAttachmentStorage(faults: faults)
            ),
            deleteService: ChoreDeleteService(chores: chores, storage: FixtureAttachmentStorage(faults: faults)),
            profiles: FixtureProfileRepository(),
            currentUserID: FixtureData.currentUserID,
            now: Date(timeIntervalSince1970: 1_790_000_000)
        )
        return (model, chores)
    }

    @Test func applyingFillsTitleDescriptionAndAssignee() {
        let (model, _) = makeModel()
        model.apply(template("Put the bins out", description: "Yellow lid", assignedTo: FixtureData.otherUserID))
        #expect(model.title == "Put the bins out")
        #expect(String(model.descriptionText.characters) == "Yellow lid")
        #expect(model.assignedTo == FixtureData.otherUserID)
        #expect(model.status == .pending)
        #expect(!model.due.hasDueDate)
    }

    @Test func aListDescriptionIsSavedExactlyAsTheFavouriteHasIt() async throws {
        let (model, chores) = makeModel()
        model.apply(template("Woolworths run", description: listDescription))
        #expect(model.isDescriptionProtected)
        #expect(model.protectedDescription == listDescription)

        await model.save()

        let saved = try #require(await chores.allChores.first)
        #expect(saved.description == listDescription)
        #expect(saved.title == "Woolworths run")
    }

    @Test func editingAProtectedFavouriteDescriptionAsTextUsesTheFavouritesText() async throws {
        let (model, chores) = makeModel()
        model.apply(template("Woolworths run", description: listDescription))
        model.beginEditingProtectedDescription()
        #expect(!model.isDescriptionProtected)
        #expect(String(model.descriptionText.characters).contains("Milk"))

        await model.save()
        let saved = try #require(await chores.allChores.first)
        #expect(saved.description?.contains("<ul>") != true)
        #expect(saved.description?.contains("Milk") == true)
    }

    @Test func aFormOpenedFromAFavouriteIsNotDirty() {
        let (model, _) = makeModel()
        model.apply(template("Woolworths run", description: listDescription, assignedTo: FixtureData.otherUserID), asBaseline: true)
        #expect(!model.isDirty)
        model.title = "Woolworths run (Sat)"
        #expect(model.isDirty)
    }

    @Test func pickingAFavouriteInsideTheFormCountsAsAChange() {
        let (model, _) = makeModel()
        model.apply(template("Put the bins out"))
        #expect(model.isDirty)
    }

    @Test func withNoFavouriteOnlyADescriptionOrAssigneeNeedsConfirming() {
        let (model, _) = makeModel()
        model.title = "Wool"
        #expect(!model.favouriteChangeNeedsConfirmation)
        model.descriptionText = AttributedString("  ")
        #expect(!model.favouriteChangeNeedsConfirmation)
        model.descriptionText = AttributedString("eggs")
        #expect(model.favouriteChangeNeedsConfirmation)
        model.descriptionText = AttributedString()
        model.assignedTo = FixtureData.currentUserID
        #expect(model.favouriteChangeNeedsConfirmation)
    }

    @Test func anUntouchedFavouriteSwapsWithoutAsking() {
        let (model, _) = makeModel()
        let woolworths = template("Woolworths run", description: listDescription)
        let bins = template("Put the bins out", description: "Yellow lid", assignedTo: FixtureData.otherUserID)
        model.apply(woolworths)
        #expect(model.appliedFavouriteID == woolworths.id)
        // It filled a description, but that's the favourite's own, not the user's.
        #expect(!model.favouriteChangeNeedsConfirmation)

        model.apply(bins)
        #expect(model.appliedFavouriteID == bins.id)
        #expect(model.title == "Put the bins out")
        #expect(!model.isDescriptionProtected)
        #expect(model.assignedTo == FixtureData.otherUserID)
    }

    @Test func changingAFavouritesFieldsMakesASwapAsk() {
        let (model, _) = makeModel()
        model.apply(template("Put the bins out", description: "Yellow lid"))
        model.descriptionText = AttributedString("Yellow lid and green lid")
        #expect(model.favouriteChangeNeedsConfirmation)

        let (other, _) = makeModel()
        other.apply(template("Put the bins out", assignedTo: nil))
        other.assignedTo = FixtureData.currentUserID
        #expect(other.favouriteChangeNeedsConfirmation)

        let (renamed, _) = makeModel()
        renamed.apply(template("Put the bins out"))
        renamed.title = "Put the bins out tonight"
        #expect(renamed.favouriteChangeNeedsConfirmation)
    }

    @Test func swappingAndClearingKeepTheDueDateStatusAndPhotos() async throws {
        let (model, _) = makeModel()
        model.due.hasDueDate = true
        model.status = .inProgress
        await model.addPhotos([(try pngData(), "a.png")])
        let due = model.due

        model.apply(template("Woolworths run", description: listDescription))
        model.apply(template("Put the bins out"))
        #expect(!model.favouriteChangeNeedsConfirmation, "date, status and photos never count as changes to replace")
        model.clearFavourite()

        #expect(model.due == due)
        #expect(model.status == .inProgress)
        #expect(model.pendingPhotos.count == 1)
    }

    @Test func clearingAFavouriteBlanksItsFields() {
        let (model, _) = makeModel()
        model.apply(template("Woolworths run", description: listDescription, assignedTo: FixtureData.otherUserID))
        model.clearFavourite()
        #expect(model.appliedFavouriteID == nil)
        #expect(model.title.isEmpty)
        #expect(model.descriptionText.characters.isEmpty)
        #expect(!model.isDescriptionProtected)
        #expect(model.protectedDescription == nil)
        #expect(model.assignedTo == nil)
        #expect(!model.favouriteChangeNeedsConfirmation)
    }

    @Test func clearingAFormOpenedFromAFavouriteCountsAsAChange() {
        let (model, _) = makeModel()
        model.apply(template("Woolworths run"), asBaseline: true)
        model.clearFavourite()
        #expect(model.isDirty)
    }

    private func pngData() throws -> Data {
        try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
    }

    @Test func applyingAPlainFavouriteAfterAListOneDropsTheProtectedDescription() async throws {
        let (model, chores) = makeModel()
        model.apply(template("Woolworths run", description: listDescription))
        model.apply(template("Put the bins out", description: "Yellow lid"))
        #expect(!model.isDescriptionProtected)
        #expect(model.protectedDescription == nil)
        await model.save()
        #expect(try #require(await chores.allChores.first).description == "Yellow lid")
    }

    @Test func favouritesNeverChangeAChoreBeingEdited() {
        let chore = Chore(
            id: UUID(), title: "Existing", description: nil, assignedTo: nil, createdBy: FixtureData.currentUserID,
            status: .pending, dueDate: nil, imageURL: nil, createdAt: Date(), updatedAt: Date()
        )
        let (model, _) = makeModel(mode: .edit(chore))
        model.apply(template("Put the bins out"))
        #expect(model.title == "Existing")
        #expect(!model.isDirty)
    }
}

// MARK: store

@MainActor
struct FavouritesStoreTests {
    private func makeStore(
        _ templates: [ChoreTemplate] = FixtureData.templates, onExpired: @escaping @MainActor () -> Void = {}
    ) -> (FavouritesStore, FixtureChoreTemplateRepository) {
        let repository = FixtureChoreTemplateRepository(templates: templates)
        return (FavouritesStore(repository: repository, profiles: FixtureProfileRepository(), onSessionExpired: onExpired), repository)
    }

    @Test func loadsInSharedOrder() async {
        let (store, _) = makeStore([template("b", order: 1), template("a", order: 0)])
        await store.load()
        #expect(store.templates.map(\.title) == ["a", "b"])
        #expect(store.loadState == .loaded)
    }

    @Test func aFailedFirstLoadIsReportedButALaterFailureKeepsTheList() async {
        let (store, repository) = makeStore()
        await repository.setFailure(.offline)
        await store.load()
        #expect(store.loadState == .failed(.offline))

        await repository.setFailure(nil)
        await store.load()
        await repository.setFailure(.offline)
        await store.load()
        #expect(store.loadState == .loaded)
        #expect(store.templates.count == 2)
    }

    @Test func addingPutsTheNewFavouriteLast() async throws {
        let (store, repository) = makeStore()
        await store.load()
        let outcome = await store.save(ChoreTemplateDraft(title: "  Water plants  ", description: nil, assignedTo: nil))
        guard case .saved(let saved) = outcome else { Issue.record("expected saved, got \(outcome)"); return }
        #expect(saved.title == "Water plants")
        #expect(saved.sortOrder == 2)
        #expect(store.templates.last?.id == saved.id)
        #expect(try await repository.fetchTemplates().count == 3)
    }

    @Test func aTitleClashInTheListIsCaughtWithoutWriting() async throws {
        let (store, repository) = makeStore()
        await store.load()
        let outcome = await store.save(ChoreTemplateDraft(title: "WOOLWORTHS RUN", description: nil, assignedTo: nil))
        #expect(outcome == .duplicate(existing: store.template(id: FixtureData.woolworthsTemplateID)))
        #expect(try await repository.fetchTemplates().count == 2)
    }

    @Test func aClashWithAFavouriteAddedElsewhereReloadsAndOffersIt() async {
        // The store hasn't loaded, as if the other phone added it after this one last looked.
        let (store, _) = makeStore()
        let outcome = await store.save(ChoreTemplateDraft(title: "put the bins out", description: nil, assignedTo: nil))
        #expect(outcome == .duplicate(existing: FixtureData.templates[1]))
        #expect(store.templates.count == 2)
    }

    @Test func editingKeepsItsOwnTitleWithoutClashing() async {
        let (store, _) = makeStore()
        await store.load()
        let outcome = await store.save(
            ChoreTemplateDraft(title: "Woolworths run", description: "Just milk", assignedTo: nil), id: FixtureData.woolworthsTemplateID
        )
        guard case .saved(let saved) = outcome else { Issue.record("expected saved"); return }
        #expect(saved.description == "Just milk")
        #expect(store.template(id: FixtureData.woolworthsTemplateID)?.description == "Just milk")
    }

    @Test func editingAFavouriteDeletedElsewhereRefreshesTheList() async {
        let (store, repository) = makeStore()
        await store.load()
        await repository.removeRemotely(id: FixtureData.binsTemplateID)
        let outcome = await store.save(
            ChoreTemplateDraft(title: "Bins", description: nil, assignedTo: nil), id: FixtureData.binsTemplateID
        )
        #expect(outcome == .failed(DataServiceError.notFound.errorDescription ?? ""))
        #expect(store.templates.map(\.id) == [FixtureData.woolworthsTemplateID])
    }

    @Test func aFailedDeletePutsTheFavouriteBack() async {
        let (store, repository) = makeStore()
        await store.load()
        await repository.setFailure(.offline)
        await store.delete(id: FixtureData.woolworthsTemplateID)
        #expect(store.templates.map(\.id) == [FixtureData.woolworthsTemplateID, FixtureData.binsTemplateID])
        #expect(store.listError?.hasPrefix("Couldn't delete that favourite.") == true)
    }

    @Test func deleteRemovesIt() async throws {
        let (store, repository) = makeStore()
        await store.load()
        await store.delete(id: FixtureData.woolworthsTemplateID)
        #expect(store.templates.map(\.id) == [FixtureData.binsTemplateID])
        #expect(try await repository.fetchTemplates().map(\.id) == [FixtureData.binsTemplateID])
    }

    @Test func movingWritesOnlyTheChangedPositions() async {
        let (store, repository) = makeStore([template("a", order: 0), template("b", order: 1), template("c", order: 2)])
        await store.load()
        let ids = store.templates.map(\.id)
        await store.move(fromOffsets: [2], toOffset: 1)
        #expect(store.templates.map(\.title) == ["a", "c", "b"])
        #expect(await repository.sortOrderWrites == [[ids[2]: 1, ids[1]: 2]])
    }

    @Test func aFailedMoveRestoresTheOrder() async {
        let (store, repository) = makeStore()
        await store.load()
        await repository.setFailure(.server)
        await store.move(fromOffsets: [0], toOffset: 2)
        #expect(store.templates.map(\.id) == [FixtureData.woolworthsTemplateID, FixtureData.binsTemplateID])
        #expect(store.listError != nil)
    }

    @Test func anExpiredSessionSignsOutInsteadOfShowingAnError() async {
        var expired = false
        let (store, repository) = makeStore(onExpired: { expired = true })
        await store.load()
        await repository.setFailure(.sessionExpired)
        await store.delete(id: FixtureData.binsTemplateID)
        #expect(expired)
        #expect(store.listError == nil)
    }
}

// MARK: editor

@MainActor
struct FavouriteEditorModelTests {
    private func makeStore() async -> (FavouritesStore, FixtureChoreTemplateRepository) {
        let repository = FixtureChoreTemplateRepository()
        let store = FavouritesStore(repository: repository, profiles: FixtureProfileRepository())
        await store.load()
        return (store, repository)
    }

    @Test func savingFromAChoreKeepsItsListDescription() async throws {
        let (store, repository) = await makeStore()
        let model = FavouriteEditorModel(
            mode: .create(ChoreTemplateDraft(title: "Aldi run", description: listDescription, assignedTo: nil)), store: store
        )
        #expect(model.isDescriptionProtected)
        #expect(!model.isDirty)

        await model.save()

        #expect(model.didFinish)
        let saved = try #require(try await repository.fetchTemplates().first { $0.title == "Aldi run" })
        #expect(saved.description == listDescription)
    }

    @Test func aBlankTitleIsRefused() async {
        let (store, _) = await makeStore()
        let model = FavouriteEditorModel(mode: .create(nil), store: store)
        model.title = "   "
        await model.save()
        #expect(model.titleError == "Title is required.")
        #expect(!model.didFinish)
    }

    @Test func aDuplicateTitleOffersToReplaceTheExistingOne() async throws {
        let (store, repository) = await makeStore()
        let model = FavouriteEditorModel(
            mode: .create(ChoreTemplateDraft(title: "woolworths run", description: "Just milk", assignedTo: FixtureData.otherUserID)),
            store: store
        )
        await model.save()
        #expect(model.duplicate?.id == FixtureData.woolworthsTemplateID)
        #expect(!model.didFinish)

        // Changing the title withdraws the offer.
        model.title = "woolworths run!"
        model.titleChanged()
        #expect(model.duplicate == nil)
        model.title = "woolworths run"
        await model.save()

        await model.replaceDuplicate()
        #expect(model.didFinish)
        let all = try await repository.fetchTemplates()
        #expect(all.count == 2)
        let replaced = try #require(all.first { $0.id == FixtureData.woolworthsTemplateID })
        #expect(replaced.description == "Just milk")
        #expect(replaced.assignedTo == FixtureData.otherUserID)
    }

    @Test func renamingOntoAnotherFavouriteMergesTheTwo() async throws {
        let (store, repository) = await makeStore()
        let model = FavouriteEditorModel(mode: .edit(try #require(store.template(id: FixtureData.binsTemplateID))), store: store)
        model.title = "Woolworths Run"
        await model.save()
        #expect(model.duplicate?.id == FixtureData.woolworthsTemplateID)

        await model.replaceDuplicate()

        let all = try await repository.fetchTemplates()
        #expect(all.map(\.id) == [FixtureData.woolworthsTemplateID])
        #expect(all.first?.description == "Yellow lid on alternate weeks.")
        #expect(store.templates.map(\.id) == [FixtureData.woolworthsTemplateID])
    }

    @Test func aFailedSaveKeepsTheSheetOpenWithAMessage() async {
        let (store, repository) = await makeStore()
        await repository.setFailure(.offline)
        let model = FavouriteEditorModel(mode: .create(nil), store: store)
        model.title = "Water plants"
        await model.save()
        #expect(!model.didFinish)
        #expect(model.errorMessage?.contains("offline") == true)
        #expect(model.title == "Water plants")
    }
}
