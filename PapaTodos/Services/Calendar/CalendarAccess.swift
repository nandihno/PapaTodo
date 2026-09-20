import EventKit

/// Whether the system add-event screen can be used. The app never asks for calendar
/// permission itself: `EKEventEditViewController` adds the event out of process and the user
/// picks the calendar there. Access the user has turned off in Settings, or that a device
/// policy blocks, is reported instead of silently ignored.
nonisolated enum CalendarAccess {
    static func current() -> CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied: .denied
        case .restricted: .restricted
        default: .available
        }
    }
}
