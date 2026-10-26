import Foundation
import Observation

/// Why a send was refused.
enum SendRefusal: Error, Equatable, LocalizedError {
    case notPending
    case approvalMismatch
    case approvalUsed
    case approvalExpired
    case bodyChanged

    var errorDescription: String? {
        switch self {
        case .notPending: "This draft isn't waiting to be sent."
        case .approvalMismatch: "This approval is out of date. Review the latest draft."
        case .approvalUsed: "This approval was already used."
        case .approvalExpired: "This draft's approval expired (older than 24 hours). Review it again."
        case .bodyChanged: "The draft changed since you approved it. Review it again."
        }
    }
}

/// THE ONLY CODE THAT SENDS EMAIL. Plain Swift, no AI.
///
/// A draft is sent only when:
/// 1. you clicked Send (Review screen or notification),
/// 2. its one-time approvalID is valid, unused and less than 24 hours old,
/// 3. its body hash matches what you approved,
/// 4. the 30-second Undo window passed without you cancelling.
@Observable
final class SendService {
    struct PendingSend: Identifiable {
        let id: String // approvalID
        let draft: Draft
        let startedAt: Date
        let deadline: Date
        let summary: String
    }

    private(set) var pending: [PendingSend] = []
    private var tasks: [String: Task<Void, Never>] = [:]

    private let sender: () -> any DraftSending
    let undoWindow: TimeInterval
    private let now: () -> Date

    var onSent: ((Draft) -> Void)?
    var onFailed: ((Draft, Error) -> Void)?
    var onUndone: ((Draft) -> Void)?

    init(sender: @escaping () -> any DraftSending, undoWindow: TimeInterval = Motion.undoWindow, now: @escaping () -> Date = Date.init) {
        self.sender = sender
        self.undoWindow = undoWindow
        self.now = now
    }

    /// Checks every rule. Returns nil when the send is allowed.
    nonisolated static func validate(
        status: DraftStatus,
        expectedStatus: DraftStatus = .pending,
        currentApprovalID: String,
        approvalUsed: Bool,
        approvalIssuedAt: Date,
        expiresAt: Date,
        storedHash: String,
        body: String,
        presentedApprovalID: String,
        presentedHash: String,
        now: Date
    ) -> SendRefusal? {
        guard status == expectedStatus else { return .notPending }
        guard presentedApprovalID == currentApprovalID else { return .approvalMismatch }
        guard !approvalUsed else { return .approvalUsed }
        guard now.timeIntervalSince(approvalIssuedAt) < Draft.approvalLifetime, now < expiresAt else { return .approvalExpired }
        let actualHash = Draft.hash(body)
        guard actualHash == storedHash, presentedHash == storedHash else { return .bodyChanged }
        return nil
    }

    private func refusal(for draft: Draft, approvalID: String, presentedHash: String, expecting status: DraftStatus) -> SendRefusal? {
        Self.validate(
            status: draft.status, expectedStatus: status, currentApprovalID: draft.approvalID,
            approvalUsed: draft.approvalUsed, approvalIssuedAt: draft.approvalIssuedAt, expiresAt: draft.expiresAt,
            storedHash: draft.bodyHash, body: draft.body, presentedApprovalID: approvalID,
            presentedHash: presentedHash, now: now()
        )
    }

    /// Step 1: you clicked Send. Starts the Undo window; nothing is sent yet.
    @discardableResult
    func requestSend(_ draft: Draft, approvalID: String, presentedHash: String) throws -> PendingSend {
        if let refusal = refusal(for: draft, approvalID: approvalID, presentedHash: presentedHash, expecting: .pending) {
            if refusal == .approvalExpired { draft.status = .expired }
            throw refusal
        }
        draft.status = .sending
        let start = now()
        let item = PendingSend(
            id: approvalID, draft: draft, startedAt: start, deadline: start.addingTimeInterval(undoWindow),
            summary: draft.email.map { "Reply to \($0.sender)" } ?? "Reply"
        )
        pending.append(item)
        let window = undoWindow
        tasks[approvalID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            } catch {
                return // Undo cancelled the task.
            }
            await self?.finish(approvalID: approvalID, presentedHash: presentedHash)
        }
        return item
    }

    /// Undo during the window. The draft goes back to pending with the same (unused) approval.
    func undo(approvalID: String) {
        guard let index = pending.firstIndex(where: { $0.id == approvalID }) else { return }
        tasks[approvalID]?.cancel()
        tasks[approvalID] = nil
        let item = pending.remove(at: index)
        if item.draft.status == .sending { item.draft.status = .pending }
        onUndone?(item.draft)
    }

    func isSending(_ draft: Draft) -> Bool {
        pending.contains { $0.draft === draft }
    }

    /// Step 2: the window passed. Re-check everything, burn the approval, then send.
    private func finish(approvalID: String, presentedHash: String) async {
        guard let index = pending.firstIndex(where: { $0.id == approvalID }) else { return }
        let item = pending.remove(at: index)
        tasks[approvalID] = nil
        let draft = item.draft
        if let refusal = refusal(for: draft, approvalID: approvalID, presentedHash: presentedHash, expecting: .sending) {
            draft.status = .pending
            onFailed?(draft, refusal)
            return
        }
        draft.approvalUsed = true
        do {
            try await sender().sendDraft(id: draft.gmailDraftID)
            draft.status = .sent
            draft.sentAt = now()
            onSent?(draft)
        } catch {
            // The approval is spent. A new one is needed to try again.
            draft.status = .pending
            draft.issueApproval(now: now())
            onFailed?(draft, error)
        }
    }
}
