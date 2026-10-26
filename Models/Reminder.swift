import Foundation
import SwiftData

@Model
final class Reminder {
    /// Stable identifier for notification actions.
    var uuid: String
    var text: String
    var dueAt: Date
    var isRecurring: Bool
    var recurrenceRaw: String
    var statusRaw: String
    var createdAt: Date
    var firedAt: Date?

    init(text: String, dueAt: Date, recurrence: Recurrence = .none, now: Date = .now) {
        self.uuid = UUID().uuidString
        self.text = text
        self.dueAt = dueAt
        self.isRecurring = recurrence != .none
        self.recurrenceRaw = recurrence.rawValue
        self.statusRaw = ReminderStatus.pending.rawValue
        self.createdAt = now
    }

    var status: ReminderStatus {
        get { ReminderStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set {
            recurrenceRaw = newValue.rawValue
            isRecurring = newValue != .none
        }
    }

    var isOpen: Bool { status != .done }
}
