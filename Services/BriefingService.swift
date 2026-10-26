import Foundation
import SwiftData

struct Briefing {
    var greeting: String
    var headline: String
    var urgent: [Email]
    var needsReply: [Email]
    var waitingDrafts: [Draft]
    var reminders: [Reminder]
    var jobUpdates: [JobApplication]

    var isAllClear: Bool {
        urgent.isEmpty && waitingDrafts.isEmpty && needsReply.isEmpty && reminders.allSatisfy { $0.status == .done }
    }
}

/// Builds the Today summary. Plain Swift, no AI.
final class BriefingService {
    func make(context: ModelContext, name: String, now: Date = .now) -> Briefing {
        make(
            emails: (try? context.fetch(FetchDescriptor<Email>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]))) ?? [],
            drafts: (try? context.fetch(FetchDescriptor<Draft>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? [],
            reminders: (try? context.fetch(FetchDescriptor<Reminder>(sortBy: [SortDescriptor(\.dueAt)]))) ?? [],
            jobs: (try? context.fetch(FetchDescriptor<JobApplication>(sortBy: [SortDescriptor(\.lastUpdate, order: .reverse)]))) ?? [],
            name: name, now: now
        )
    }

    /// Pure version used by the live Today screen and tests.
    func make(emails: [Email], drafts: [Draft], reminders: [Reminder], jobs: [JobApplication], name: String, now: Date = .now) -> Briefing {
        let open = emails.filter { !$0.isDone && !$0.isFlagged }
        let urgent = open.filter { $0.effectiveLabel == .urgent }
        let needsReply = open.filter { $0.effectiveLabel == .needsReply && $0.pendingDraft == nil }
        let waiting = drafts.filter { $0.status == .pending }

        let cal = Calendar.current
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        let todays = reminders.filter {
            ($0.dueAt <= endOfToday && $0.status != .done) || ($0.status == .done && cal.isDate($0.dueAt, inSameDayAs: now))
        }
        let since = now.addingTimeInterval(-3 * 86400)
        let jobUpdates = jobs.filter { $0.lastUpdate >= since }

        let hour = cal.component(.hour, from: now)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let greeting = name.isEmpty ? part : "\(part), \(name)"

        let headline: String
        switch (urgent.count, waiting.count) {
        case (0, 0): headline = "Nothing urgent. You're all caught up."
        case (0, let d): headline = "\(d) \(d == 1 ? "reply is" : "replies are") drafted and waiting for your OK."
        case (let u, 0): headline = "\(u) urgent \(u == 1 ? "email needs" : "emails need") you today."
        case (let u, let d): headline = "\(u) urgent, \(d) \(d == 1 ? "draft" : "drafts") ready to review."
        }

        return Briefing(greeting: greeting, headline: headline, urgent: urgent, needsReply: needsReply,
                        waitingDrafts: waiting, reminders: todays, jobUpdates: jobUpdates)
    }

    /// Short text for the morning notification.
    func notificationBody(_ b: Briefing) -> String {
        var parts: [String] = []
        if !b.urgent.isEmpty { parts.append("\(b.urgent.count) urgent") }
        if !b.waitingDrafts.isEmpty { parts.append("\(b.waitingDrafts.count) drafts to review") }
        let openReminders = b.reminders.filter { $0.status != .done }.count
        if openReminders > 0 { parts.append("\(openReminders) reminders today") }
        if !b.jobUpdates.isEmpty { parts.append("\(b.jobUpdates.count) job updates") }
        return parts.isEmpty ? "All clear today. Enjoy! 🐶" : parts.joined(separator: " · ")
    }
}
