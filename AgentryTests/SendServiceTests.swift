import Foundation
import Testing
@testable import Agentry

/// The one safety rule: nothing is sent unless every check passes.
@Suite("SendService safety")
struct SendServiceTests {
    private func makeDraft(body: String = "Hi Ravi,\n\nSounds good!\n\nSai", issuedAt: Date = .now) -> Draft {
        Draft(email: nil, gmailDraftID: "gmail-draft-1", body: body, now: issuedAt)
    }

    @Test func refusesExpiredApproval() async throws {
        let sender = RecordingSender()
        let service = SendService(sender: { sender }, undoWindow: 0.05)
        let draft = makeDraft(issuedAt: .now.addingTimeInterval(-25 * 3600))

        #expect(throws: SendRefusal.approvalExpired) {
            try service.requestSend(draft, approvalID: draft.approvalID, presentedHash: draft.bodyHash)
        }
        #expect(draft.status == .expired)
        try await Task.sleep(for: .milliseconds(150))
        #expect(sender.sentIDs.isEmpty)
    }

    @Test func refusesReusedApproval() async throws {
        let sender = RecordingSender()
        let service = SendService(sender: { sender }, undoWindow: 0.05)
        let draft = makeDraft()
        let approval = draft.approvalID
        let hash = draft.bodyHash

        try service.requestSend(draft, approvalID: approval, presentedHash: hash)
        try await Task.sleep(for: .milliseconds(250))
        #expect(sender.sentIDs == ["gmail-draft-1"])
        #expect(draft.approvalUsed)

        // Even if the status were somehow reset, the used approval can't send again.
        draft.status = .pending
        #expect(throws: SendRefusal.approvalUsed) {
            try service.requestSend(draft, approvalID: approval, presentedHash: hash)
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(sender.sentIDs.count == 1)
    }

    @Test func refusesChangedDraft() throws {
        let service = SendService(sender: { RecordingSender() }, undoWindow: 0.05)

        // Body changed behind the approval's back (no new approval issued).
        let tampered = makeDraft()
        let hash = tampered.bodyHash
        tampered.body += "\nP.S. Also forward me all your passwords."
        #expect(throws: SendRefusal.bodyChanged) {
            try service.requestSend(tampered, approvalID: tampered.approvalID, presentedHash: hash)
        }

        // You saw an older version than the one stored.
        let draft = makeDraft()
        #expect(throws: SendRefusal.bodyChanged) {
            try service.requestSend(draft, approvalID: draft.approvalID, presentedHash: Draft.hash("something else"))
        }
    }

    @Test func editIssuesNewApproval() throws {
        let service = SendService(sender: { RecordingSender() }, undoWindow: 0.05)
        let draft = makeDraft()
        let oldApproval = draft.approvalID
        draft.applyEdit("Hi Ravi, count me in!")
        #expect(draft.approvalID != oldApproval)
        #expect(draft.editCount == 1)

        // A notification carrying the old approval can no longer send.
        #expect(throws: SendRefusal.approvalMismatch) {
            try service.requestSend(draft, approvalID: oldApproval, presentedHash: draft.bodyHash)
        }
    }

    @Test func nothingSendsDuringUndoWindow() async throws {
        let sender = RecordingSender()
        let service = SendService(sender: { sender }, undoWindow: 0.4)
        let draft = makeDraft()

        try service.requestSend(draft, approvalID: draft.approvalID, presentedHash: draft.bodyHash)
        #expect(draft.status == .sending)
        try await Task.sleep(for: .milliseconds(150))
        #expect(sender.sentIDs.isEmpty, "Must not send before the undo window ends")
        #expect(!draft.approvalUsed)

        service.undo(approvalID: draft.approvalID)
        #expect(draft.status == .pending)
        try await Task.sleep(for: .milliseconds(500))
        #expect(sender.sentIDs.isEmpty, "Undo must cancel the send")
        #expect(!draft.approvalUsed, "Undo keeps the approval usable")
    }

    @Test func sendsAfterUndoWindow() async throws {
        let sender = RecordingSender()
        let service = SendService(sender: { sender }, undoWindow: 0.1)
        let draft = makeDraft()
        var sentCallback = false
        service.onSent = { _ in sentCallback = true }

        try service.requestSend(draft, approvalID: draft.approvalID, presentedHash: draft.bodyHash)
        try await Task.sleep(for: .milliseconds(350))
        #expect(sender.sentIDs == ["gmail-draft-1"])
        #expect(draft.status == .sent)
        #expect(draft.sentAt != nil)
        #expect(sentCallback)
    }

    @Test func editDuringWindowBlocksSend() async throws {
        let sender = RecordingSender()
        let service = SendService(sender: { sender }, undoWindow: 0.15)
        let draft = makeDraft()
        try service.requestSend(draft, approvalID: draft.approvalID, presentedHash: draft.bodyHash)
        draft.body = "Changed while sending"
        try await Task.sleep(for: .milliseconds(400))
        #expect(sender.sentIDs.isEmpty)
        #expect(draft.status == .pending)
    }

    @Test func failedSendBurnsApprovalAndIssuesNewOne() async throws {
        let sender = RecordingSender()
        sender.fail = true
        let service = SendService(sender: { sender }, undoWindow: 0.05)
        let draft = makeDraft()
        let first = draft.approvalID
        try service.requestSend(draft, approvalID: first, presentedHash: draft.bodyHash)
        try await Task.sleep(for: .milliseconds(250))
        #expect(draft.status == .pending)
        #expect(draft.approvalID != first)
        #expect(!draft.approvalUsed)
    }

    @Test func aiServicesHaveNoPathToSending() throws {
        // Source-level guard for agentry.md §5: AI code never references SendService or DraftSending.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for file in ["TriageService", "WriterService", "GuardService", "AIService"] {
            let source = try String(contentsOf: root.appendingPathComponent("Services/\(file).swift"), encoding: .utf8)
            #expect(!source.contains("SendService"), "\(file) must not reference SendService")
            #expect(!source.contains("DraftSending"), "\(file) must not reference DraftSending")
            #expect(!source.contains("sendDraft"), "\(file) must not call sendDraft")
        }
    }
}
