import SwiftUI

/// Launch-argument hooks for UI tests. They only change presentation and are harmless in
/// normal use because the arguments are never passed.
enum UITestHooks {
    /// `-UITestDarkMode` forces dark appearance from inside the app, because switching the
    /// simulator's own appearance is unreliable. It is applied to the signed-in screens only:
    /// forcing it over the sign-in screen made the keyboard transition between appearances and
    /// intermittently stalled UI tests while typing the password.
    static var forcedColorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains("-UITestDarkMode") ? .dark : nil
    }

    /// How long the detail screen's "Up to date" notice stays. `-UITestLongConfirmation` keeps it
    /// up long enough for a UI test to find it: fixture fetches finish during the push animation.
    static var upToDateConfirmation: Duration {
        ProcessInfo.processInfo.arguments.contains("-UITestLongConfirmation") ? .seconds(8) : .seconds(2)
    }
}
