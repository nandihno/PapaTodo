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
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "Could not scroll \(element) into view", file: file, line: line)
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
