import Foundation
import SwiftData

/// One email you labeled with "Correct label", exported for the eval tests.
nonisolated struct LabeledEmail: Codable, Sendable {
    var sender: String
    var senderAddress: String
    var subject: String
    var body: String
    /// What Agentry's AI said at triage time.
    var aiLabel: String?
    /// What you said.
    var label: String
}

/// Numbers from agentry.md §10. Shared by the Settings screen and the eval tests.
nonisolated enum EvalMetrics {
    /// Fraction of emails where the AI label matched your label.
    static func triageAccuracy(_ pairs: [(ai: EmailLabel?, truth: EmailLabel)]) -> Double? {
        let scored = pairs.filter { $0.ai != nil }
        guard !scored.isEmpty else { return nil }
        return Double(scored.filter { $0.ai == $0.truth }.count) / Double(scored.count)
    }

    /// Drafts sent without edits ÷ drafts you handled (sent or rejected).
    static func draftAcceptance(sentUnedited: Int, sentEdited: Int, rejected: Int) -> Double? {
        let shown = sentUnedited + sentEdited + rejected
        guard shown > 0 else { return nil }
        return Double(sentUnedited) / Double(shown)
    }

    /// Detection rate on tricky emails and false-alarm rate on normal ones.
    static func detection(flaggedTricky: Int, totalTricky: Int, flaggedNormal: Int, totalNormal: Int) -> (detection: Double, falseAlarm: Double) {
        (Double(flaggedTricky) / Double(max(totalTricky, 1)), Double(flaggedNormal) / Double(max(totalNormal, 1)))
    }

    /// ~/Library/Application Support/Agentry/eval/triage_labels.json (never in the repo).
    static var labelsFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Agentry/eval/triage_labels.json")
    }

    static func loadSavedLabels() -> [LabeledEmail] {
        guard let data = try? Data(contentsOf: labelsFile) else { return [] }
        return (try? JSONDecoder().decode([LabeledEmail].self, from: data)) ?? []
    }
}

extension EvalMetrics {
    /// Write every email you corrected to the labels file.
    @MainActor
    static func exportLabels(from context: ModelContext) {
        let emails = (try? context.fetch(FetchDescriptor<Email>(predicate: #Predicate { $0.userLabelRaw != nil }))) ?? []
        let rows = emails.compactMap { e -> LabeledEmail? in
            guard let truth = e.userLabelRaw else { return nil }
            return LabeledEmail(sender: e.sender, senderAddress: e.senderAddress, subject: e.subject,
                                body: MailText.trimForModel(e.body, maxChars: 2000), aiLabel: e.labelRaw, label: truth)
        }
        let url = labelsFile
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(rows).write(to: url, options: .atomic)
    }
}
