import EventKit
import EventKitUI
import SwiftUI

// MARK: - Termin w Kalendarzu iPhone'a
//
// Review 11.10.2026: terminy „mają być w kalendarzu”. Kalendarz kancelarii jest
// w Emmie, ale rozprawa powinna być też tam, gdzie adwokat patrzy na cały dzień
// (Kalendarz iPhone'a, zegarek, CarPlay). Systemowe okno `EKEventEditViewController`
// pokazuje gotowy wpis do potwierdzenia — od iOS 17 nie wymaga dostępu do
// kalendarza, więc Emma nie widzi prywatnych wydarzeń użytkownika i nie pyta o zgodę.

enum SystemCalendarExport {

    /// Wpis do Kalendarza iPhone'a z terminu Emmy (godzina w strefie kancelarii).
    static func makeEvent(
        _ event: ScheduledEvent,
        clientName: String?,
        reminder: ReminderOffset,
        store: EKEventStore
    ) -> EKEvent {
        let entry = EKEvent(eventStore: store)
        entry.title = event.title
        entry.timeZone = FirmDateTime.timeZone
        let start = FirmDateTime.date(day: event.day, time: event.isAllDay ? TimeOfDay(minutes: 0)! : event.time)
        entry.startDate = start
        entry.isAllDay = event.isAllDay
        entry.endDate = event.isAllDay
            ? start
            : start.addingTimeInterval(TimeInterval(max(event.durationMinutes, 15) * 60))
        if !event.place.isEmpty { entry.location = event.place }
        var notes = [event.kind.displayTitle]
        if let clientName { notes.append("Klient: \(clientName)") }
        notes.append("Dodano z aplikacji Emma.")
        entry.notes = notes.joined(separator: "\n")
        if reminder != .none {
            entry.addAlarm(EKAlarm(relativeOffset: -TimeInterval(reminder.rawValue * 60)))
        }
        return entry
    }
}

/// Systemowe okno nowego wydarzenia, wypełnione danymi terminu.
struct SystemCalendarEditor: UIViewControllerRepresentable {
    let event: ScheduledEvent
    let clientName: String?
    let reminder: ReminderOffset
    let onFinish: (EKEventEditViewAction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = SystemCalendarExport.makeEvent(event, clientName: clientName, reminder: reminder, store: store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (EKEventEditViewAction) -> Void

        init(onFinish: @escaping (EKEventEditViewAction) -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action)
        }
    }
}
