import XCTest

final class PapaTodosUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFixtures"]
        app.launch()
    }

    @MainActor
    func testFixtureSignInAndSignOutFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFixtures"]
        app.launch()

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

        XCTAssertTrue(app.staticTexts["status.choreCount"].waitForExistence(timeout: 5)
                      || app.otherElements["status.choreCount"].waitForExistence(timeout: 1))

        app.buttons["status.signOut"].tap()
        XCTAssertTrue(app.buttons["signin.submit"].waitForExistence(timeout: 5))
    }
}
