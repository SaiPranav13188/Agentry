import Foundation

/// Parsed, validated triage outcome.
nonisolated struct TriageOutcome: Sendable, Equatable {
    var label: EmailLabel
    var reason: String
    var deadline: Date?
    var isJobEmail: Bool
    var jobCompany: String
    var jobRole: String
    var jobStage: JobStage?
}

/// AI part 1: one call per email → label, reason, deadline, job info.
final class TriageService {
    private let ai: any AIBackend
    private let userName: () -> String

    /// Apple's on-device model has ~4k tokens; keep the email well under that.
    static let maxEmailChars = 2400

    init(ai: any AIBackend, userName: @escaping () -> String = { "the user" }) {
        self.ai = ai
        self.userName = userName
    }

    func triage(_ email: EmailInput) async throws -> TriageOutcome {
        let raw = try await ai.triage(makePrompt(email), email: email)
        var outcome = Self.parse(raw)
        // Small models like to invent deadlines; keep one only if the email talks about one.
        if !Self.mentionsDeadline(email.subject + " " + email.body) { outcome.deadline = nil }
        return outcome
    }

    nonisolated static func mentionsDeadline(_ text: String) -> Bool {
        text.range(of: "\\b(due|deadline|by|before|until|no later than|expires?|last date|within)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    func makePrompt(_ email: EmailInput) -> AIPrompt {
        AIPrompt(
            instructions: PromptLibrary.render(PromptLibrary.load("triage"), ["user": userName()]),
            prompt: "Classify this email.\n\n" + PromptLibrary.dataBlock(email, maxChars: Self.maxEmailChars),
            isLong: email.body.count > Self.maxEmailChars
        )
    }

    /// Normalize whatever the model returned into safe, typed values.
    nonisolated static func parse(_ r: TriageResult) -> TriageOutcome {
        let label = EmailLabel.parse(r.label) ?? .fyi
        var reason = r.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = reason.firstIndex(where: { ".!?".contains($0) }) {
            reason = String(reason[...end])
        }
        if reason.count > 140 { reason = String(reason.prefix(139)) + "…" }
        if reason.isEmpty { reason = "No reason given." }
        reason = reason.prefix(1).uppercased() + reason.dropFirst()

        let stage = JobStage.parse(r.jobStage == "none" ? nil : r.jobStage)
        let isJob = r.isJobEmail && (stage != nil || !r.jobCompany.isEmpty)

        return TriageOutcome(
            label: label,
            reason: reason,
            deadline: parseDate(r.deadline),
            isJobEmail: isJob,
            jobCompany: r.jobCompany.trimmingCharacters(in: .whitespacesAndNewlines),
            jobRole: r.jobRole.trimmingCharacters(in: .whitespacesAndNewlines),
            jobStage: isJob ? (stage ?? .applied) : nil
        )
    }

    nonisolated static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.lowercased() != "none", s.lowercased() != "null" else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        for format in ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return ISO8601DateFormatter().date(from: s)
    }
}
