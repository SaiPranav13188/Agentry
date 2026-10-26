import CryptoKit
import Foundation
import SwiftData

@Model
final class Draft {
    /// Stable identifier for notifications and lookups.
    var uuid: String
    var email: Email?
    var gmailDraftID: String
    var body: String
    /// The first version the AI wrote (used for the acceptance-rate eval).
    var originalBody: String
    /// SHA-256 of `body` at the moment the current approvalID was issued.
    var bodyHash: String
    /// One-time ID. Any edit issues a new one.
    var approvalID: String
    var approvalIssuedAt: Date
    var approvalUsed: Bool
    var statusRaw: String
    var expiresAt: Date
    var createdAt: Date
    var sentAt: Date?
    var editCount: Int

    static let approvalLifetime: TimeInterval = 24 * 60 * 60

    init(email: Email?, gmailDraftID: String, body: String, now: Date = .now) {
        self.uuid = UUID().uuidString
        self.email = email
        self.gmailDraftID = gmailDraftID
        self.body = body
        self.originalBody = body
        self.bodyHash = Draft.hash(body)
        self.approvalID = UUID().uuidString
        self.approvalIssuedAt = now
        self.approvalUsed = false
        self.statusRaw = DraftStatus.pending.rawValue
        self.expiresAt = now.addingTimeInterval(Draft.approvalLifetime)
        self.createdAt = now
        self.sentAt = nil
        self.editCount = 0
    }

    var status: DraftStatus {
        get { DraftStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var wasEdited: Bool { body != originalBody }

    /// Issue a fresh one-time approval for the current body.
    func issueApproval(now: Date = .now) {
        approvalID = UUID().uuidString
        approvalIssuedAt = now
        approvalUsed = false
        bodyHash = Draft.hash(body)
        expiresAt = now.addingTimeInterval(Draft.approvalLifetime)
    }

    /// Replace the body (your edit or an AI revision) and issue a new approval.
    func applyEdit(_ newBody: String, now: Date = .now) {
        guard newBody != body else { return }
        body = newBody
        editCount += 1
        issueApproval(now: now)
    }

    nonisolated static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
