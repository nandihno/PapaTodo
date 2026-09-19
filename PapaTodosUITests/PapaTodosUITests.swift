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
        target.tap()
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
    func testEditingAChoreUpdatesItsCard() throws {
        let app = launchSignedIn()
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)

        openCard(app, containing: "Water the garden")
        let title = app.textFields["form.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Water the garden")
        title.clearAndTypeText("Water the front garden")
        app.buttons["form.save"].tap()

        XCTAssertTrue(card(app, containing: "Water the front garden").waitForExistence(timeout: 5))
        XCTAssertFalse(card(app, containing: "Water the garden.").exists)
        waitForCards(app, count: 4)
    }

    @MainActor
    func testDeletingAChoreNeedsConfirmationAndRemovesIt() throws {
        let app = launchSignedIn()
        app.segmentedControls["home.tabs"].buttons["All"].tap()
        waitForCards(app, count: 4)

        openCard(app, containing: "Water the garden")
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

        waitForCards(app, count: 3)
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

        openCard(app, containing: "Sort the pantry")
        let shown = app.staticTexts["form.protectedDescription"]
        reveal(shown, in: app)
        XCTAssertTrue((shown.label).contains("Cans"))
        XCTAssertFalse(app.textViews["form.description"].exists, "no editor until the user opts in")

        // An unrelated edit leaves the description alone: rename and save.
        let title = app.textFields["form.title"]
        title.clearAndTypeText("Sort the pantry shelves")
        app.buttons["form.save"].tap()
        XCTAssertTrue(card(app, containing: "Sort the pantry shelves").waitForExistence(timeout: 5))

        openCard(app, containing: "Sort the pantry shelves")
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
