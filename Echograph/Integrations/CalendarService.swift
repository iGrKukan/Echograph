import EventKit
import Foundation

enum CalendarService {
    enum Failure: LocalizedError {
        case accessDenied
        case noDefaultCalendar
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Echograph couldn't access Calendar. Open Settings → Privacy & Security → Calendars to grant access."
            case .noDefaultCalendar:
                return "No default Calendar is configured on this device."
            case .saveFailed(let detail):
                return "Couldn't save event: \(detail)"
            }
        }
    }

    static func addEvent(
        title: String,
        startDate: Date,
        duration: TimeInterval,
        notes: String?
    ) async throws {
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
        }
        guard granted else { throw Failure.accessDenied }

        guard let calendar = store.defaultCalendarForNewEvents else {
            throw Failure.noDefaultCalendar
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(max(60, duration))
        event.notes = notes
        event.calendar = calendar

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw Failure.saveFailed(error.localizedDescription)
        }
    }
}
