import Foundation
import SwiftData

nonisolated struct ParsedReminder: Sendable, Equatable {
    var text: String
    var dueAt: Date
    var recurrence: Recurrence
}

/// "Remind me Friday at 4 to call Ravi" → one AI call → text + date (Asia/Kolkata) + recurrence.
final class ReminderService {
    private let ai: any AIBackend

    nonisolated static let timeZone = TimeZone(identifier: "Asia/Kolkata")!
    /// How late a reminder can be delivered before it's marked "late".
    nonisolated static let lateThreshold: TimeInterval = 120

    nonisolated static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    nonisolated static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }

    init(ai: any AIBackend) {
        self.ai = ai
    }

    func parse(_ input: String, now: Date = .now) async -> ParsedReminder? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let weekday = now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))
        let prompt = AIPrompt(
            instructions: PromptLibrary.render(PromptLibrary.load("reminder"), [
                "now": Self.formatter.string(from: now),
                "weekday": weekday,
            ]),
            prompt: "Reminder request: \(text)"
        )
        if let r = try? await ai.reminder(prompt, text: text, now: now),
           let due = Self.formatter.date(from: r.dueAt.trimmingCharacters(in: .whitespaces)),
           due > now.addingTimeInterval(-60) {
            let cleaned = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedReminder(text: cleaned.isEmpty ? text : cleaned, dueAt: due, recurrence: Recurrence.parse(r.recurrence))
        }
        return Self.fallbackParse(text, now: now)
    }

    /// No-AI parsing with NSDataDetector ("tomorrow 5pm", "Friday at 4", "in 2 hours").
    nonisolated static func fallbackParse(_ input: String, now: Date) -> ParsedReminder? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["remind me to ", "remind me ", "reminder: ", "reminder "] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        let recurrence: Recurrence = {
            let l = text.lowercased()
            if l.contains("every weekday") { return .weekdays }
            if l.contains("every day") || l.contains("daily") || l.contains("every morning") || l.contains("every evening") { return .daily }
            if l.contains("every week") || l.contains("weekly") || l.range(of: "every (monday|tuesday|wednesday|thursday|friday|saturday|sunday)", options: .regularExpression) != nil { return .weekly }
            if l.contains("every month") || l.contains("monthly") { return .monthly }
            return .none
        }()

        // "in 2 hours" / "in 30 minutes"
        if let r = text.range(of: "in (\\d+) (minutes?|mins?|hours?|hrs?|days?)", options: [.regularExpression, .caseInsensitive]) {
            let parts = text[r].split(separator: " ")
            if parts.count == 3, let n = Double(parts[1]) {
                let unit = parts[2].lowercased()
                let seconds = unit.hasPrefix("m") ? n * 60 : unit.hasPrefix("h") ? n * 3600 : n * 86400
                let rest = text.replacingCharacters(in: r, with: "")
                return ParsedReminder(text: tidyText(rest), dueAt: now.addingTimeInterval(seconds), recurrence: recurrence)
            }
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let match = matches.first, var date = match.date, let range = Range(match.range, in: text) else { return nil }
        let phrase = text[range].lowercased()
        let hasTime = phrase.range(of: "\\d", options: .regularExpression) != nil && (phrase.contains(":") || phrase.contains("am") || phrase.contains("pm") || phrase.contains("at"))
        let cal = calendar
        if !hasTime {
            date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        } else {
            // "at 4" with no am/pm → afternoon.
            let hour = cal.component(.hour, from: date)
            if !phrase.contains("am"), !phrase.contains("pm"), hour < 8 {
                date = date.addingTimeInterval(12 * 3600)
            }
        }
        while date < now { date = cal.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(7 * 86400) }
        let rest = text.replacingCharacters(in: range, with: "")
        return ParsedReminder(text: tidyText(rest), dueAt: date, recurrence: recurrence)
    }

    private nonisolated static func tidyText(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["every day", "every weekday", "every week", "every month", "daily", "weekly", "monthly"] {
            t = t.replacingOccurrences(of: junk, with: "", options: .caseInsensitive)
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for prefix in ["to ", "that ", "about "] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Reminder" : t.prefix(1).uppercased() + t.dropFirst()
    }

    // MARK: - Delivery

    /// Every minute: deliver due reminders. Returns those delivered (late ones flagged).
    @discardableResult
    func deliverDue(in context: ModelContext, now: Date = .now) -> [Reminder] {
        let pending = ReminderStatus.pending.rawValue
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.statusRaw == pending && $0.dueAt <= now })
        let due = (try? context.fetch(descriptor)) ?? []
        for reminder in due {
            reminder.status = now.timeIntervalSince(reminder.dueAt) > Self.lateThreshold ? .late : .fired
            reminder.firedAt = now
        }
        return due
    }

    func markDone(_ reminder: Reminder, in context: ModelContext, now: Date = .now) {
        reminder.status = .done
        scheduleNext(after: reminder, in: context, now: now)
    }

    func snooze(_ reminder: Reminder, by interval: TimeInterval = 3600, now: Date = .now) {
        reminder.dueAt = now.addingTimeInterval(interval)
        reminder.status = .pending
        reminder.firedAt = nil
    }

    private func scheduleNext(after reminder: Reminder, in context: ModelContext, now: Date) {
        guard var next = reminder.recurrence.next(after: reminder.dueAt, calendar: Self.calendar) else { return }
        while next <= now {
            guard let n = reminder.recurrence.next(after: next, calendar: Self.calendar) else { return }
            next = n
        }
        context.insert(Reminder(text: reminder.text, dueAt: next, recurrence: reminder.recurrence, now: now))
    }
}
