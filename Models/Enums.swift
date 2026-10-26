import SwiftUI

/// Triage label for an email.
nonisolated enum EmailLabel: String, Codable, CaseIterable, Identifiable, Sendable {
    case urgent
    case needsReply = "needs_reply"
    case fyi
    case ignore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgent: "Urgent"
        case .needsReply: "Needs reply"
        case .fyi: "FYI"
        case .ignore: "Ignore"
        }
    }

    var symbol: String {
        switch self {
        case .urgent: "flame.fill"
        case .needsReply: "arrowshape.turn.up.left.fill"
        case .fyi: "info.circle.fill"
        case .ignore: "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .urgent: .red
        case .needsReply: .orange
        case .fyi: .teal
        case .ignore: .gray
        }
    }

    var wantsDraft: Bool { self == .urgent || self == .needsReply }

    /// Lenient parsing for AI output ("Needs Reply", "needs-reply", "reply" ...).
    nonisolated static func parse(_ raw: String) -> EmailLabel? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch s {
        case "urgent", "important", "critical": return .urgent
        case "needs_reply", "needsreply", "reply", "needs_response", "respond": return .needsReply
        case "fyi", "info", "informational", "for_your_information": return .fyi
        case "ignore", "spam", "promotion", "promotional", "newsletter", "none": return .ignore
        default: return nil
        }
    }
}

nonisolated enum GuardVerdict: String, Codable, CaseIterable, Sendable {
    case safe, suspicious, malicious

    var isFlagged: Bool { self != .safe }

    nonisolated static func parse(_ raw: String) -> GuardVerdict {
        let s = raw.lowercased()
        if s.contains("malicious") { return .malicious }
        if s.contains("suspicious") || s.contains("unsafe") { return .suspicious }
        return .safe
    }
}

nonisolated enum DraftStatus: String, Codable, Sendable {
    case pending, sending, sent, rejected, expired
}

nonisolated enum ReminderStatus: String, Codable, Sendable {
    /// Waiting for its time.
    case pending
    /// Delivered on time, not yet acknowledged.
    case fired
    /// Delivered after its time (the Mac was asleep or Agentry was closed).
    case late
    case done
}

nonisolated enum Recurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, daily, weekdays, weekly, monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Once"
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    nonisolated static func parse(_ raw: String) -> Recurrence {
        let s = raw.lowercased()
        if s.contains("weekday") { return .weekdays }
        if s.contains("day") || s.contains("daily") { return .daily }
        if s.contains("week") { return .weekly }
        if s.contains("month") { return .monthly }
        return .none
    }

    /// The next occurrence after `date`.
    func next(after date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .none: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .weekdays:
            var d = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(d) {
                d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        }
    }
}

nonisolated enum JobStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case applied, assessment, interview, offer, rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applied: "Applied"
        case .assessment: "Assessment"
        case .interview: "Interview"
        case .offer: "Offer"
        case .rejected: "Rejected"
        }
    }

    var symbol: String {
        switch self {
        case .applied: "paperplane.fill"
        case .assessment: "pencil.and.list.clipboard"
        case .interview: "person.2.wave.2.fill"
        case .offer: "party.popper.fill"
        case .rejected: "xmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .applied: .blue
        case .assessment: .purple
        case .interview: .orange
        case .offer: .green
        case .rejected: .gray
        }
    }

    /// Position in the pipeline. Rejected and offer are terminal.
    var order: Int {
        switch self {
        case .applied: 0
        case .assessment: 1
        case .interview: 2
        case .offer: 3
        case .rejected: 3
        }
    }

    nonisolated static func parse(_ raw: String?) -> JobStage? {
        guard let s = raw?.lowercased(), !s.isEmpty else { return nil }
        if s.contains("offer") { return .offer }
        if s.contains("reject") || s.contains("declin") || s.contains("unsuccessful") { return .rejected }
        if s.contains("interview") { return .interview }
        if s.contains("assess") || s.contains("test") || s.contains("assignment") || s.contains("challenge") { return .assessment }
        if s.contains("appl") { return .applied }
        return nil
    }
}

nonisolated enum ActivityKind: String, Codable, Sendable {
    case fetch, triage, draft, send, reject, guardFlag, reminder, job, system, error

    var symbol: String {
        switch self {
        case .fetch: "tray.and.arrow.down.fill"
        case .triage: "tag.fill"
        case .draft: "square.and.pencil"
        case .send: "paperplane.fill"
        case .reject: "trash.fill"
        case .guardFlag: "exclamationmark.shield.fill"
        case .reminder: "bell.fill"
        case .job: "briefcase.fill"
        case .system: "gearshape.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .fetch: .blue
        case .triage: .indigo
        case .draft: .purple
        case .send: .green
        case .reject: .gray
        case .guardFlag: .red
        case .reminder: .orange
        case .job: .brown
        case .system: .secondary
        case .error: .red
        }
    }
}
