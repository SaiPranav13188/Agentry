import Foundation
import SwiftData

/// AI part 2: writes a reply in your style and saves it as a Gmail draft.
/// It can create, update and delete drafts. It has no way to send them.
final class WriterService {
    private let ai: any AIBackend
    private let mail: () -> any MailProvider
    private let settings: AppSettings

    private var styleCache: (examples: [String], fetchedAt: Date)?

    init(ai: any AIBackend, mail: @escaping () -> any MailProvider, settings: AppSettings) {
        self.ai = ai
        self.mail = mail
        self.settings = settings
    }

    /// 1–2 short recent sent emails, cached for an hour.
    func styleExamples() async -> [String] {
        if let cache = styleCache, cache.fetchedAt.timeIntervalSinceNow > -3600 { return cache.examples }
        let examples = (try? await mail().recentSentBodies(limit: 2)) ?? []
        styleCache = (examples, .now)
        return examples
    }

    func makePrompt(for email: EmailInput, examples: [String], revision: (current: String, instruction: String)? = nil) -> AIPrompt {
        let instructions = PromptLibrary.render(PromptLibrary.load("writer"), [
            "user": settings.userName,
            "firstName": settings.firstName,
            "signoff": settings.signOff,
        ])
        var prompt = ""
        if !examples.isEmpty {
            prompt += "Style examples (emails \(settings.firstName) wrote before):\n"
            for (i, e) in examples.prefix(2).enumerated() {
                prompt += "--- Example \(i + 1) ---\n\(MailText.trimForModel(e, maxChars: 400))\n"
            }
            prompt += "\n"
        }
        prompt += "Write a reply to this email:\n" + PromptLibrary.dataBlock(email, maxChars: 1800)
        if let revision {
            prompt += "\n\nCurrent draft:\n\(revision.current)\n\nRewrite the draft with this change: \(revision.instruction)"
        }
        prompt += "\n\nSIGN_OFF: \(settings.signOff)\n\(settings.firstName)"
        return AIPrompt(instructions: instructions, prompt: prompt, isLong: email.body.count > 1800)
    }

    func writeReply(to email: EmailInput) async throws -> String {
        let examples = await styleExamples()
        let result = try await ai.draft(makePrompt(for: email, examples: examples), email: email, revision: nil)
        return Self.ensureSignature(Self.tidy(result.body), firstName: settings.firstName)
    }

    /// Write a reply and create the Gmail draft. Returns the new Draft (status pending).
    func createDraft(for email: Email, in context: ModelContext) async throws -> Draft {
        let body = try await writeReply(to: email.input)
        let gmailID = try await mail().createDraft(reply: email.replyContext, body: body)
        let draft = Draft(email: email, gmailDraftID: gmailID, body: body)
        context.insert(draft)
        return draft
    }

    /// "Ask AI to change…" — returns the revised body (the caller applies it, which issues a new approval).
    func revise(_ draft: Draft, instruction: String) async throws -> String {
        guard let email = draft.email else { return draft.body }
        let examples = await styleExamples()
        let prompt = makePrompt(for: email.input, examples: examples, revision: (draft.body, instruction))
        let body = Self.tidy(try await ai.draft(prompt, email: email.input, revision: instruction).body)
        return Self.ensureSignature(body, firstName: settings.firstName)
    }

    /// Push an edited body to the Gmail draft.
    func syncDraft(_ draft: Draft) async throws {
        guard let email = draft.email else { return }
        try await mail().updateDraft(id: draft.gmailDraftID, reply: email.replyContext, body: draft.body)
    }

    func discardDraft(_ draft: Draft) async throws {
        try await mail().deleteDraft(id: draft.gmailDraftID)
    }

    /// Small models often stop after "Best,". Make sure the reply is signed.
    nonisolated static func ensureSignature(_ body: String, firstName: String) -> String {
        guard !firstName.isEmpty else { return body }
        let tail = body.components(separatedBy: "\n").suffix(2).joined(separator: " ").lowercased()
        if tail.contains(firstName.lowercased()) { return body }
        if body.hasSuffix(",") { return body + "\n" + firstName }
        return body
    }

    nonisolated static func tidy(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("subject:"), let nl = s.firstIndex(of: "\n") {
            s = String(s[nl...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
}
