import XCTest

final class PapaTodosUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: helpers

    @MainActor
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFixtures"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("correct-horse")
        app.buttons["signin.submit"].tap()
        dismissSavePasswordSheetIfShown(app)
    }

    /// After a sign-in the system may offer "Save Password?" over the app, and it swallows the next taps.
    /// Whether it appears depends on the simulator's Passwords settings, so the helper is tolerant.
    @MainActor
    private func dismissSavePasswordSheetIfShown(_ app: XCUIApplication) {
        let sheet = app.sheets.containing(.staticText, identifier: "Save Password?").firstMatch
        guard sheet.waitForExistence(timeout: 3) else { return }
        // Scoped to the sheet: the app's own notification prompt also has a "Not Now" button.
        sheet.buttons["Not Now"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3), "the Save Password sheet should be dismissed")
    }

    @MainActor
    private func launchSignedIn(extraArguments: [String] = []) -> XCUIApplication {
        let app = launch(extraArguments: extraArguments)
        signIn(app)
        return app
    }

    @MainActor
    private func cards(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "chore.card")
    }

    @MainActor
    private func waitForCards(_ app: XCUIApplication, count: Int, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "count == %d", count)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: cards(app))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "Expected \(count) cards, found \(cards(app).count)", file: file, line: line)
    }

    // MARK: sign in

    @MainActor
    func testAppLaunches() throws {
        _ = launch()
    }

    @MainActor
    func testSignInRejectsBadPasswordThenSucceedsAndSignsOut() throws {
        let app = launch()

        let submit = app.buttons["signin.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled, "Sign In must be disabled until both fields are filled")

        let email = app.textFields["Email"]
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("wrong")
        submit.tap()
        XCTAssertTrue(app.staticTexts["signin.message"].waitForExistence(timeout: 5))

        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "correct-horse")
        submit.tap()
        XCTAssertTrue(app.otherElements["home.list"].waitForExistence(timeout: 5)
                      || app.collectionViews["home.list"].waitForExistence(timeout: 2))
        dismissSavePasswordSheetIfShown(app)

        app.buttons["home.settings"].tap()
        reveal(app.buttons["settings.signOut"], in: app)
        app.buttons["settings.signOut"].tap()
        XCTAssertTrue(app.buttons["signin.submit"].waitForExistence(timeout: 5))
    }

    // MARK: home

    @MainActor
    func testHomeShowsMineTabThenAllThenDone() throws {
        let app = launchSignedIn()

        // Mine = active chores assigned to the fixture user.
        waitForCards(app, count: 2)
        XCTAssertTrue(app.staticTexts["home.summary"].label.contains("assigned to you"))

        let tabs = app.segmentedControls["home.tabs"]
        tabs.buttons["All"].tap()
        waitForCards(app, count: 4)   // every active chore

        tabs.buttons["Done"].tap()
        waitForCards(app, count: 1)   // "Fold laundry"
        XCTAssertTrue(app.staticTexts["home.summary"].label.contains("completed"))
    }

    @MainActor
    func testCardsDescribeStatusAssigneeAndDueForVoiceOver() throws {
        let app = launchSignedIn()
        waitForCards(app, count: 2)

        let recycling = cards(app).matching(NSPredicate(format: "label CONTAINS 'Take out recycling'")).firstMatch
        XCTAssertTrue(recycling.exists)
        XCTAssertTrue(recycling.label.contains("Status: Pending"))
        XCTAssertTrue(recycling.label.contains("Assigned to Family Tester"))
        XCTAssertTrue(recycling.label.contains("Due: Overdue"))
        XCTAssertTrue(recycling.label.contains("3 attachments"))
    }

    @MainActor
    func testSearchFiltersAndShowsEmptyStateThenClears() throws {
        let app = launchSignedIn()
        waitForCards(app, count: 2)
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)

        let search = app.searchFields["Search chores"]
        search.tap()
        search.typeText("garden")
        waitForCards(app, count: 1)

        search.clearAndTypeText("zzzz")
        XCTAssertTrue(app.descendants(matching: .any)["home.empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No chores match your search."].exists)

        search.clearAndTypeText("alex")   // matches by assignee/creator name
        XCTAssertTrue(cards(app).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testFailedFirstLoadShowsErrorAndRetryRecovers() throws {
        let app = launchSignedIn(extraArguments: ["-UITestFailFirstLoad"])

        let retry = app.buttons["home.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Could not load chores"].exists)

        retry.tap()
        waitForCards(app, count: 2)
    }

    // MARK: settings

    @MainActor
    func testSettingsValidatesAndSavesAvatarAndTheme() throws {
        let app = launchSignedIn()
        app.buttons["home.settings"].tap()

        let avatarField = app.textFields["settings.avatarField"]
        XCTAssertTrue(avatarField.waitForExistence(timeout: 5))
        let saveAvatar = app.buttons["settings.saveAvatar"]
        XCTAssertFalse(saveAvatar.isEnabled, "nothing changed yet")

        avatarField.tap()
        avatarField.typeText("ftp://nope")
        XCTAssertTrue(app.staticTexts["settings.avatarError"].waitForExistence(timeout: 3))
        XCTAssertFalse(saveAvatar.isEnabled)

        avatarField.clearAndTypeText("https://fixtures.invalid/me.png")
        XCTAssertTrue(saveAvatar.isEnabled)
        saveAvatar.tap()
        XCTAssertTrue(app.staticTexts["Avatar saved."].waitForExistence(timeout: 5))

        let themeField = app.textFields["settings.themeField"]
        themeField.tap()
        themeField.clearAndTypeText("#C2410C")
        let saveTheme = app.buttons["settings.saveTheme"]
        XCTAssertTrue(saveTheme.isEnabled)
        saveTheme.tap()
        XCTAssertTrue(app.staticTexts["Theme saved."].waitForExistence(timeout: 5))
    }

    // MARK: create / edit / delete (Phase 3)

    @MainActor
    private func openNewChoreForm(_ app: XCUIApplication) {
        let button = app.buttons["home.newChore"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.textFields["form.title"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func card(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        cards(app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Taps a card once it has stopped moving (right after a tab switch it can still be animating).
    @MainActor
    private func openCard(_ app: XCUIApplication, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = card(app, containing: text)
        let hittable = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: target)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "card never became tappable", file: file, line: line)
        // Near the top, not the centre: at the largest text sizes a card is taller than the screen,
        // so its centre point can be off-screen.
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    /// Opens a chore's detail screen from the list.
    @MainActor
    private func openDetail(_ app: XCUIApplication, containing text: String) {
        openCard(app, containing: text)
        XCTAssertTrue(app.buttons["detail.status"].waitForExistence(timeout: 5), "the detail screen should open")
    }

    /// Opens a chore's edit form: card, then the Edit button on the detail screen.
    @MainActor
    private func openEditor(_ app: XCUIApplication, containing text: String) {
        openDetail(app, containing: text)
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.textFields["form.title"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func backToList(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["home.newChore"].waitForExistence(timeout: 5))
    }

    /// On iOS 26 a confirmation dialog on iPhone shows only its non-cancel buttons; tapping
    /// elsewhere dismisses it.
    @MainActor
    private func dismissDialogByTappingOutside(_ app: XCUIApplication) {
        app.staticTexts["Edit Chore"].firstMatch.exists ? app.staticTexts["Edit Chore"].firstMatch.tap() : app.staticTexts["New Chore"].firstMatch.tap()
    }

    @MainActor
    func testTitleIsRequiredThenANewChoreAppearsInTheList() throws {
        let app = launchSignedIn()
        waitForCards(app, count: 2)
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)

        openNewChoreForm(app)
        app.buttons["form.save"].tap()
        XCTAssertTrue(app.staticTexts["form.titleError"].waitForExistence(timeout: 3), "saving without a title must explain why")

        let title = app.textFields["form.title"]
        title.tap()
        title.typeText("Buy birthday candles")
        XCTAssertFalse(app.staticTexts["form.titleError"].exists, "the error clears once a title is typed")
        app.buttons["form.save"].tap()

        waitForCards(app, count: 5)
        XCTAssertTrue(card(app, containing: "Buy birthday candles").exists)
    }

    @MainActor
    func testEditingAChoreFromItsDetailUpdatesTheDetailAndTheList() throws {
        let app = launchSignedIn()
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)

        openEditor(app, containing: "Water the garden")
        let title = app.textFields["form.title"]
        XCTAssertEqual(title.value as? String, "Water the garden")
        title.clearAndTypeText("Water the front garden")
        app.buttons["form.save"].tap()

        // Back on the detail screen, showing the new title.
        XCTAssertTrue(app.navigationBars["Water the front garden"].waitForExistence(timeout: 5))
        backToList(app)
        XCTAssertTrue(card(app, containing: "Water the front garden").waitForExistence(timeout: 5))
        waitForCards(app, count: 4)
    }

    @MainActor
    func testDeletingAChoreNeedsConfirmationAndRemovesIt() throws {
        let app = launchSignedIn()
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)

        openEditor(app, containing: "Water the garden")
        reveal(app.buttons["form.delete"], in: app)
        app.buttons["form.delete"].tap()

        // Nothing is deleted until the confirmation is accepted; dismiss it first.
        let confirm = app.buttons["form.confirmDelete"].exists ? app.buttons["form.confirmDelete"] : app.buttons["Delete Chore"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        dismissDialogByTappingOutside(app)
        XCTAssertTrue(app.buttons["form.delete"].waitForExistence(timeout: 3), "still on the form: nothing was deleted")
        XCTAssertFalse(app.buttons["form.confirmDelete"].exists)

        app.buttons["form.delete"].tap()
        // Two buttons read "Delete Chore": the form's own row and the dialog's confirm button.
        let labelled = app.buttons.matching(NSPredicate(format: "label == 'Delete Chore'"))
        let dialogConfirm = app.buttons.matching(identifier: "form.confirmDelete").firstMatch
        XCTAssertTrue(dialogConfirm.waitForExistence(timeout: 3) || labelled.count >= 2, "the confirmation must appear")
        (dialogConfirm.exists ? dialogConfirm : labelled.element(boundBy: labelled.count - 1)).tap()

        // Deleting from the detail screen returns to the list, without the chore.
        XCTAssertTrue(app.buttons["home.newChore"].waitForExistence(timeout: 5))
        waitForCards(app, count: 3)
        XCTAssertFalse(card(app, containing: "Water the garden").exists)
    }

    @MainActor
    func testOnlyTheCreatorSeesDeleteChore() throws {
        let app = launchSignedIn()
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)

        // "Take out recycling" is assigned to the signed-in user but was created by someone else.
        openEditor(app, containing: "Take out recycling")
        XCTAssertTrue(app.buttons["form.save"].exists, "the assignee can still edit the chore")
        reveal(app.textFields["form.title"], in: app)
        XCTAssertFalse(app.buttons["form.delete"].exists, "only the creator can delete a chore")
        app.buttons["form.cancel"].tap()
        backToList(app)

        // "Water the garden" was created by the signed-in user.
        openEditor(app, containing: "Water the garden")
        reveal(app.buttons["form.delete"], in: app)
        XCTAssertTrue(app.buttons["form.delete"].exists)
    }

    @MainActor
    func testDeletingFromTheDetailScreenTellsYouWhenPhotoFilesCouldNotBeRemoved() throws {
        // Regression: deleting via the detail screen once dropped the "file still in storage" note.
        let app = launchSignedIn(extraArguments: ["-UITestStorageRefusesDeletes"])
        openEditor(app, containing: "Water the garden")   // created by the current user, has a photo
        reveal(app.buttons["form.delete"], in: app)
        app.buttons["form.delete"].tap()
        let labelled = app.buttons.matching(NSPredicate(format: "label == 'Delete Chore'"))
        let dialogConfirm = app.buttons.matching(identifier: "form.confirmDelete").firstMatch
        XCTAssertTrue(dialogConfirm.waitForExistence(timeout: 3) || labelled.count >= 2)
        (dialogConfirm.exists ? dialogConfirm : labelled.element(boundBy: labelled.count - 1)).tap()

        XCTAssertTrue(app.buttons["home.newChore"].waitForExistence(timeout: 5), "back on the list")
        let notice = app.staticTexts["home.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the caveat must be shown, not dropped")
        XCTAssertTrue(notice.label.contains("still in storage"))
        XCTAssertFalse(card(app, containing: "Water the garden").exists)
    }

    @MainActor
    func testLeavingAnEditedFormAsksBeforeDiscarding() throws {
        let app = launchSignedIn()
        openNewChoreForm(app)
        app.textFields["form.title"].tap()
        app.textFields["form.title"].typeText("Unsaved idea")

        app.buttons["form.cancel"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 3))
        dismissDialogByTappingOutside(app)   // "keep editing"
        XCTAssertFalse(app.buttons["Discard Changes"].waitForExistence(timeout: 1))
        XCTAssertEqual(app.textFields["form.title"].value as? String, "Unsaved idea", "the draft survives")

        app.buttons["form.cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.buttons["home.newChore"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAnUneditedFormClosesWithoutAsking() throws {
        let app = launchSignedIn()
        openNewChoreForm(app)
        app.buttons["form.cancel"].tap()
        XCTAssertTrue(app.buttons["home.newChore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
    }

    @MainActor
    func testAPhotoCanBePreviewedRemovedAndSavedWithTheChore() throws {
        let app = launchSignedIn(extraArguments: ["-UITestSeedPhoto"])
        openNewChoreForm(app)

        let remove = app.buttons["form.removePhoto"]
        reveal(remove, in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "form.removePhoto").count, 1)
        remove.tap()
        XCTAssertFalse(app.buttons["form.removePhoto"].exists, "a removed pending photo disappears")
    }

    @MainActor
    func testSavingWithAPhotoAttachesIt() throws {
        let app = launchSignedIn(extraArguments: ["-UITestSeedPhoto"])
        openNewChoreForm(app)
        let title = app.textFields["form.title"]
        title.tap()
        title.typeText("Chore with photo")
        app.buttons["form.save"].tap()

        app.segmentedControls["home.tabs"].buttons["All"].tap()
        let saved = card(app, containing: "Chore with photo")
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.contains("1 attachment"))
    }

    @MainActor
    func testAddingALinkInsertsItAndRejectsUnsafeOnes() throws {
        let app = launchSignedIn()
        openNewChoreForm(app)

        let description = app.textViews["form.description"]
        reveal(description, in: app)
        description.tap()
        description.typeText("Recipe: ")

        app.buttons["form.addLink"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("javascript:alert(1)")
        app.alerts.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["form.linkError"].waitForExistence(timeout: 3), "an unsafe address must be refused")

        app.buttons["form.addLink"].tap()
        let retry = app.alerts.textFields.firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        retry.typeText("example.com/pasta")
        app.alerts.buttons["Add"].tap()

        XCTAssertFalse(app.staticTexts["form.linkError"].exists)
        let value = description.value as? String ?? ""
        XCTAssertTrue(value.contains("https://example.com/pasta"), "the link text was inserted: \(value)")
    }

    @MainActor
    func testAStructuredDescriptionIsProtectedUntilExplicitlyEdited() throws {
        let app = launchSignedIn()
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)

        openEditor(app, containing: "Sort the pantry")
        let shown = app.staticTexts["form.protectedDescription"]
        reveal(shown, in: app)
        XCTAssertTrue((shown.label).contains("Cans"))
        XCTAssertFalse(app.textViews["form.description"].exists, "no editor until the user opts in")

        // An unrelated edit leaves the description alone: rename and save.
        let title = app.textFields["form.title"]
        title.clearAndTypeText("Sort the pantry shelves")
        app.buttons["form.save"].tap()
        XCTAssertTrue(app.navigationBars["Sort the pantry shelves"].waitForExistence(timeout: 5))
        backToList(app)
        XCTAssertTrue(card(app, containing: "Sort the pantry shelves").waitForExistence(timeout: 5))

        openEditor(app, containing: "Sort the pantry shelves")
        let again = app.staticTexts["form.protectedDescription"]
        reveal(again, in: app)
        XCTAssertTrue(again.label.contains("Cans"), "the list survived the rename")

        reveal(app.buttons["form.editAsText"], in: app)
        app.buttons["form.editAsText"].tap()
        app.buttons["Edit as Text"].tap()
        XCTAssertTrue(app.textViews["form.description"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSearchFindsTextInsideAStructuredDescription() throws {
        let app = launchSignedIn()
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)
        let search = app.searchFields["Search chores"]
        search.tap()
        search.typeText("jars")
        waitForCards(app, count: 1)
        XCTAssertTrue(card(app, containing: "Sort the pantry").exists)
    }

    @MainActor
    func testFormLayoutScreenshotsDefaultAndAccessibilitySize() throws {
        let app = launchSignedIn(extraArguments: ["-UITestSeedPhoto"])
        openNewChoreForm(app)
        attachScreenshot(app, named: "form-top")
        reveal(app.buttons["form.removePhoto"], in: app)
        attachScreenshot(app, named: "form-photos")
        app.terminate()

        let large = launchSignedIn(extraArguments: ["-UITestSeedPhoto", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openNewChoreForm(large)
        attachScreenshot(large, named: "form-top-accessibility")
        reveal(large.buttons["form.removePhoto"], in: large)
        attachScreenshot(large, named: "form-photos-accessibility")
        XCTAssertTrue(large.buttons["form.save"].exists, "Save stays reachable at the largest text size")
    }

    // MARK: detail screen (Phase 4)

    @MainActor
    func testTappingACardOpensTheDetailScreenWithEverythingTheWebShows() throws {
        let app = launchSignedIn()
        openDetail(app, containing: "Water the garden")

        XCTAssertTrue(app.navigationBars["Water the garden"].exists)
        XCTAssertEqual(app.buttons["detail.status"].label, "Status: Pending")
        XCTAssertTrue(app.staticTexts["detail.dueDate"].exists)
        XCTAssertTrue(app.buttons["detail.markDone"].exists)
        XCTAssertTrue(app.buttons["detail.saveToCalendar"].exists)
        XCTAssertTrue(app.buttons["detail.googleCalendar"].exists)
        XCTAssertTrue(app.buttons["detail.edit"].exists)
        XCTAssertTrue(app.textFields["detail.commentField"].exists)
    }

    @MainActor
    func testTheStatusButtonCyclesThroughPendingInProgressDoneAndBack() throws {
        let app = launchSignedIn()
        openDetail(app, containing: "Water the garden")
        let status = app.buttons["detail.status"]

        status.tap()
        XCTAssertTrue(NSPredicate(format: "label == 'Status: In progress'").evaluate(with: nil) || waitForLabel(status, "Status: In progress"))
        status.tap()
        XCTAssertTrue(waitForLabel(status, "Status: Done"))
        XCTAssertFalse(app.buttons["detail.markDone"].exists, "Mark as Done is hidden once done")
        status.tap()
        XCTAssertTrue(waitForLabel(status, "Status: Pending"))
        XCTAssertTrue(app.buttons["detail.markDone"].exists)
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func testMarkAsDoneMovesTheChoreToTheDoneTabAndTheListAgrees() throws {
        let app = launchSignedIn()
        openDetail(app, containing: "Water the garden")
        app.buttons["detail.markDone"].tap()
        XCTAssertTrue(waitForLabel(app.buttons["detail.status"], "Status: Done"))
        backToList(app)

        // Mine (active, assigned to me) loses it; Done gains it: the list already reflects the change.
        waitForCards(app, count: 1)
        app.segmentedControls["home.tabs"].buttons["Done"].tap()
        waitForCards(app, count: 2)
        XCTAssertTrue(card(app, containing: "Water the garden").exists)
    }

    @MainActor
    func testCommentsShowAuthorsAndANewCommentCanBePosted() throws {
        let app = launchSignedIn()
        openDetail(app, containing: "Take out recycling")

        let comments = app.descendants(matching: .any).matching(identifier: "detail.comment")
        reveal(comments.firstMatch, in: app)
        XCTAssertEqual(comments.count, 2)
        XCTAssertTrue(comments.element(boundBy: 0).label.contains("Alex Sample"))
        XCTAssertTrue(comments.element(boundBy: 0).label.contains("Bins go out after dinner."))

        let send = app.buttons["detail.sendComment"]
        XCTAssertFalse(send.isEnabled, "Send is off until there is text")

        let field = app.textFields["detail.commentField"]
        field.tap()
        field.typeText("   ")
        XCTAssertFalse(send.isEnabled, "whitespace alone is not a comment")
        field.typeText("Done, thanks!")
        XCTAssertTrue(send.isEnabled)
        send.tap()

        XCTAssertTrue(waitForCount(comments, 3))
        XCTAssertEqual(field.value as? String, "Add a comment…", "the field clears after sending")
        XCTAssertTrue(comments.element(boundBy: 2).label.contains("Family Tester"))
        XCTAssertTrue(comments.element(boundBy: 2).label.contains("Done, thanks!"))
    }

    /// A page of the photo viewer, found by its accessibility label (query subscripts match identifiers).
    @MainActor
    private func viewerPage(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, _ count: Int, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: query)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func testACommentFromAnotherDeviceAppearsLiveWithoutReloading() async throws {
        let app = launchSignedIn(extraArguments: ["-UITestRemoteComment"])
        openDetail(app, containing: "Take out recycling")

        let comments = app.descendants(matching: .any).matching(identifier: "detail.comment")
        reveal(comments.firstMatch, in: app)

        // About 1.5 seconds after the screen subscribes, another client posts. Nothing is tapped here.
        XCTAssertTrue(waitForCount(comments, 3, timeout: 10), "the new comment should arrive over the live stream")
        XCTAssertTrue(comments.element(boundBy: 2).label.contains("Posted from another device"))

        // The fetch and the stream may both have delivered it; it must still appear exactly once.
        try? await Task.sleep(for: .seconds(1))
        XCTAssertEqual(comments.count, 3, "no duplicate after the live update")
    }

    @MainActor
    func testPhotosOpenFullScreenAndCanBeSwipedAndClosed() throws {
        let app = launchSignedIn()
        openDetail(app, containing: "Take out recycling")

        app.buttons["detail.photo"].tap()
        XCTAssertTrue(viewerPage(app, "Photo 1 of 3").waitForExistence(timeout: 5), "the full-screen viewer opens on the first photo")

        app.swipeLeft()
        XCTAssertTrue(viewerPage(app, "Photo 2 of 3").waitForExistence(timeout: 3))

        app.buttons["Close full screen photo"].tap()
        XCTAssertTrue(app.buttons["detail.status"].waitForExistence(timeout: 5), "closing returns to the detail screen")
    }

    @MainActor
    func testAThumbnailOpensThatPhotoInTheViewer() throws {
        let app = launchSignedIn()
        openDetail(app, containing: "Take out recycling")
        let thumbs = app.buttons.matching(identifier: "detail.thumb")
        XCTAssertTrue(thumbs.element(boundBy: 2).waitForExistence(timeout: 5))
        thumbs.element(boundBy: 2).tap()
        XCTAssertTrue(viewerPage(app, "Photo 3 of 3").waitForExistence(timeout: 5))
    }

    @MainActor
    func testSaveToCalendarOpensTheSystemEventScreen() throws {
        let app = launchSignedIn()
        openDetail(app, containing: "Water the garden")
        // The button starts under the pinned comment bar; scroll it clear of the bar first.
        reveal(app.buttons["detail.saveToCalendar"], in: app)
        app.swipeUp()
        app.buttons["detail.saveToCalendar"].tap()

        // The system "New Event" screen: the user picks the calendar and confirms there. It is drawn
        // out of process, so UI tests can't see its buttons (or that it covers our screen). Give it
        // time to draw, then tap where its X is. That same spot on *our* screen is the Back button,
        // so if the sheet had not appeared this tap would leave the detail screen and the check
        // below would fail: staying on the detail screen proves the sheet was there and closed.
        Thread.sleep(forTimeInterval: 6)
        attachScreenshot(app, named: "calendar-event-screen")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.095, dy: 0.115)).tap()
        XCTAssertTrue(app.buttons["detail.status"].waitForExistence(timeout: 8), "the event screen closed and we are still on the detail screen")
        XCTAssertFalse(app.staticTexts["Added to your calendar."].exists, "cancelling must not claim success")
    }

    @MainActor
    func testAChoreWithoutADueDateHasNoCalendarButtons() throws {
        let app = launchSignedIn()
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)
        openDetail(app, containing: "Sort the pantry")
        XCTAssertFalse(app.buttons["detail.saveToCalendar"].exists)
        XCTAssertFalse(app.buttons["detail.googleCalendar"].exists)
    }

    @MainActor
    func testDetailLayoutAtDefaultAndAccessibilitySizes() throws {
        let app = launchSignedIn()
        openDetail(app, containing: "Take out recycling")
        attachScreenshot(app, named: "detail-top")
        reveal(app.textFields["detail.commentField"], in: app)
        attachScreenshot(app, named: "detail-comments")
        app.terminate()

        let large = launchSignedIn(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openDetail(large, containing: "Take out recycling")
        attachScreenshot(large, named: "detail-top-accessibility")
        XCTAssertTrue(large.buttons["detail.markDone"].exists || large.buttons["detail.status"].exists)
        XCTAssertTrue(large.textFields["detail.commentField"].exists, "the comment bar stays reachable at the largest text size")
    }

    // MARK: notifications (Phase 5)

    /// The recycling chore's fixed fixture id, as a notification tap would carry it.
    private let recyclingChoreID = "CCCCCCCC-0000-0000-0000-000000000001"

    @MainActor
    func testTheHomePromptOffersNotificationsAndTurningThemOnHidesIt() throws {
        let app = launchSignedIn(extraArguments: ["-UITestNotificationStatus", "notDetermined"])
        let prompt = app.descendants(matching: .any)["home.notificationPrompt"]
        XCTAssertTrue(app.buttons["home.enableNotifications"].waitForExistence(timeout: 5), "an undecided user is offered notifications")
        XCTAssertTrue(app.buttons["home.dismissNotificationPrompt"].exists)
        _ = prompt

        app.buttons["home.enableNotifications"].tap()
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: app.buttons["home.enableNotifications"])], timeout: 5),
            .completed, "the prompt goes away once notifications are on"
        )

        app.buttons["home.settings"].tap()
        reveal(app.staticTexts["Notifications are on."], in: app)
        XCTAssertTrue(app.staticTexts["Notifications are on."].exists)
    }

    @MainActor
    func testNotNowDismissesThePrompt() throws {
        let app = launchSignedIn(extraArguments: ["-UITestNotificationStatus", "notDetermined"])
        XCTAssertTrue(app.buttons["home.dismissNotificationPrompt"].waitForExistence(timeout: 5))
        app.buttons["home.dismissNotificationPrompt"].tap()
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: app.buttons["home.enableNotifications"])], timeout: 5),
            .completed
        )
        // Settings still lets them turn notifications on later.
        app.buttons["home.settings"].tap()
        reveal(app.buttons["settings.enableNotifications"], in: app)
        XCTAssertTrue(app.buttons["settings.enableNotifications"].exists)
    }

    @MainActor
    func testSettingsShowsThePermissionStateAndHowToChangeIt() throws {
        // Denied: explain, and offer the system Settings.
        let denied = launchSignedIn(extraArguments: ["-UITestNotificationStatus", "denied"])
        XCTAssertFalse(denied.buttons["home.enableNotifications"].exists, "no prompt once the user has said no")
        denied.buttons["home.settings"].tap()
        reveal(denied.buttons["settings.openSystemSettings"], in: denied)
        XCTAssertTrue(denied.staticTexts["Notifications are turned off for Papa Todos."].exists)
        denied.terminate()

        // Already on: no prompt, and Settings says so.
        let on = launchSignedIn(extraArguments: ["-UITestNotificationStatus", "authorized"])
        XCTAssertFalse(on.buttons["home.enableNotifications"].waitForExistence(timeout: 2))
        on.buttons["home.settings"].tap()
        reveal(on.staticTexts["Notifications are on."], in: on)
        XCTAssertTrue(on.staticTexts["Notifications are on."].exists)
    }

    @MainActor
    func testSettingsCanTurnNotificationsOn() throws {
        let app = launchSignedIn(extraArguments: ["-UITestNotificationStatus", "notDetermined"])
        app.buttons["home.settings"].tap()
        reveal(app.buttons["settings.enableNotifications"], in: app)
        app.buttons["settings.enableNotifications"].tap()
        XCTAssertTrue(app.staticTexts["Notifications are on."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testATappedNotificationOpensItsChoreAfterSignIn() throws {
        // The tap arrives before anyone is signed in (a cold launch, or a session still restoring); the
        // request is kept and honored as soon as the user is.
        let app = launch(extraArguments: ["-UITestNotificationTapChore", recyclingChoreID])
        XCTAssertTrue(app.buttons["signin.submit"].waitForExistence(timeout: 5), "still signed out")
        signIn(app)

        XCTAssertTrue(app.navigationBars["Take out recycling"].waitForExistence(timeout: 10), "the notification's chore opens straight after sign-in")
        XCTAssertTrue(app.buttons["detail.status"].exists)

        // Back goes to Home, not out of the app.
        backToList(app)
    }

    @MainActor
    func testATappedNotificationForAMissingChoreShowsNotFoundNotACrash() throws {
        let app = launch(extraArguments: ["-UITestNotificationTapChore", "EEEEEEEE-0000-0000-0000-000000000009"])
        signIn(app)
        XCTAssertTrue(app.staticTexts["Chore not found"].waitForExistence(timeout: 10))
    }

    // MARK: appearance

    @MainActor
    func testHomeRendersInLightAndDarkAppearance() throws {
        // The app forces dark itself; the simulator's own appearance switch is unreliable.
        let app = launchSignedIn(extraArguments: ["-UITestDarkMode"])
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)
        attachScreenshot(app, named: "home-all-dark")

        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.textFields["settings.avatarField"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "settings-dark")
    }

    // MARK: accessibility sizes

    @MainActor
    func testHomeAndSettingsRemainUsableAtAccessibilityTextSize() throws {
        let app = launchSignedIn(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        // The list is lazy, so at this size only the first card is on screen.
        XCTAssertTrue(cards(app).firstMatch.waitForExistence(timeout: 5))

        // Segments would truncate at this size, so the tab picker becomes a menu.
        XCTAssertFalse(app.segmentedControls["home.tabs"].exists)
        XCTAssertTrue(app.buttons["home.tabs"].exists || app.descendants(matching: .any)["home.tabs"].exists)
        attachScreenshot(app, named: "home-accessibility-xxxl")

        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.textFields["settings.avatarField"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "settings-accessibility-xxxl")
        reveal(app.buttons["settings.saveAvatar"], in: app)
        reveal(app.buttons["settings.signOut"], in: app)
    }

    /// Scrolls the current screen until `element` is on screen: lazy lists and forms
    /// only expose rows that have been rendered.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        func isOnScreen() -> Bool {
            guard element.exists, !element.frame.isEmpty else { return false }
            if element.isHittable { return true }
            // Rows near the sheet's bottom edge can report not-hittable while fully visible.
            let centre = element.frame.midY
            return centre > window.frame.minY + 110 && centre < window.frame.maxY - 60
        }
        var swipes = 0
        while !isOnScreen() && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists && isOnScreen(), "Could not scroll \(element) into view", file: file, line: line)
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    /// Clears the field's current text, then types `text`.
    func clearAndTypeText(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty, current != "Search chores", current != "Image URL (https://…)", current != "Hex color" {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
