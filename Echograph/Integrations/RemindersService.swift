import EventKit
import Foundation

enum RemindersService {
    enum Failure: LocalizedError {
        case accessDenied
        case noDefaultList
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Echograph couldn't access Reminders. Open Settings → Privacy & Security → Reminders to grant access."
            case .noDefaultList:
                return "No default Reminders list is configured on this device."
            case .saveFailed(let detail):
                return "Couldn't save reminder: \(detail)"
            }
        }
    }

    static func addReminder(title: String, notes: String?) async throws {
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { ok, _ in cont.resume(returning: ok) }
            }
        }
        guard granted else { throw Failure.accessDenied }

        guard let list = store.defaultCalendarForNewReminders() else {
            throw Failure.noDefaultList
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = list

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw Failure.saveFailed(error.localizedDescription)
        }
    }
}
