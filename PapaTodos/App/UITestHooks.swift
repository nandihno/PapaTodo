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
}
