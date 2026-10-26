import Foundation
import SwiftData

@Model
final class Email {
    @Attribute(.unique) var gmailID: String
    var threadID: String
    var sender: String
    var senderAddress: String
    var subject: String
    var snippet: String
    /// Clean plain text (quoted replies and signatures removed).
    var body: String
    /// RFC 822 Message-ID header, used to thread replies.
    var messageIDHeader: String
    var receivedAt: Date

    /// nil until triage has run.
    var labelRaw: String?
    var reason: String
    var deadline: Date?
    var processedAt: Date?
    var isJobEmail: Bool

    var guardVerdictRaw: String
    var guardReason: String

    /// The label you set with "Correct label" (used for evals).
    var userLabelRaw: String?
    var isDone: Bool
    var isRead: Bool

    @Relationship(deleteRule: .cascade, inverse: \Draft.email)
    var drafts: [Draft] = []

    init(
        gmailID: String,
        threadID: String,
        sender: String,
        senderAddress: String,
        subject: String,
        snippet: String,
        body: String,
        messageIDHeader: String = "",
        receivedAt: Date = .now
    ) {
        self.gmailID = gmailID
        self.threadID = threadID
        self.sender = sender
        self.senderAddress = senderAddress
        self.subject = subject
        self.snippet = snippet
        self.body = body
        self.messageIDHeader = messageIDHeader
        self.receivedAt = receivedAt
        self.labelRaw = nil
        self.reason = ""
        self.deadline = nil
        self.processedAt = nil
        self.isJobEmail = false
        self.guardVerdictRaw = GuardVerdict.safe.rawValue
        self.guardReason = ""
        self.userLabelRaw = nil
        self.isDone = false
        self.isRead = false
    }

    var label: EmailLabel? {
        get { labelRaw.flatMap(EmailLabel.init(rawValue:)) }
        set { labelRaw = newValue?.rawValue }
    }

    var userLabel: EmailLabel? {
        get { userLabelRaw.flatMap(EmailLabel.init(rawValue:)) }
        set { userLabelRaw = newValue?.rawValue }
    }

    /// What the UI shows: your correction wins over the AI.
    var effectiveLabel: EmailLabel? { userLabel ?? label }

    var guardVerdict: GuardVerdict {
        get { GuardVerdict(rawValue: guardVerdictRaw) ?? .safe }
        set { guardVerdictRaw = newValue.rawValue }
    }

    var isFlagged: Bool { guardVerdict.isFlagged }

    var pendingDraft: Draft? {
        drafts.first { $0.status == .pending || $0.status == .sending }
    }

    var input: EmailInput {
        EmailInput(sender: sender, senderAddress: senderAddress, subject: subject, body: body, receivedAt: receivedAt)
    }

    var senderFirstName: String {
        let name = sender.isEmpty ? senderAddress : sender
        return name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// Sendable snapshot of an email handed to AI code.
nonisolated struct EmailInput: Sendable, Equatable {
    var sender: String
    var senderAddress: String
    var subject: String
    var body: String
    var receivedAt: Date
}
