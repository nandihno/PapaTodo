import EventKit
import EventKitUI
import SwiftUI

/// The system "Add Event" screen, prefilled from a `CalendarEventDraft`. The user picks the
/// calendar and confirms there. `saved` is reported only when the system says the event was
/// actually saved.
struct EventEditView: UIViewControllerRepresentable {
    let draft: CalendarEventDraft
    let onFinish: (CalendarSaveResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.notes = draft.notes
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        // EventKit's all-day end date is the start of the last day, not the exclusive next day.
        event.endDate = draft.isAllDay
            ? (Calendar.current.date(byAdding: .day, value: -1, to: draft.end) ?? draft.start)
            : draft.end
        event.alarms = draft.alarmOffsets.map { EKAlarm(relativeOffset: $0) }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (CalendarSaveResult) -> Void

        init(onFinish: @escaping (CalendarSaveResult) -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            switch action {
            case .saved: onFinish(.saved)
            case .canceled, .deleted: onFinish(.cancelled)
            @unknown default: onFinish(.failed("The calendar didn't confirm the event was saved."))
            }
        }
    }
}
