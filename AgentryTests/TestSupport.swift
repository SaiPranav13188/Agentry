import Foundation
import SwiftData
@testable import Agentry

/// AI backend that returns canned answers and records the prompts it saw.
final class MockAI: AIBackend {
    var kind: AIBackendKind { .basic }
    var triageResult = TriageResult(label: "fyi", reason: "Just info.", deadline: "", isJobEmail: false, jobCompany: "", jobRole: "", jobStage: "none")
    var draftBody = "Hi,\n\nThanks!\n\nBest,\nSai"
    var guardResult = GuardAIResult(verdict: "safe", reason: "Looks fine.")
    var reminderResult = ReminderParseResult(text: "Call Ravi", dueAt: "2030-01-04T16:00", recurrence: "none")
    var shouldThrow = false
    private(set) var prompts: [AIPrompt] = []

    func triage(_ prompt: AIPrompt, email: EmailInput) async throws -> TriageResult {
        prompts.append(prompt)
        if shouldThrow { throw URLError(.timedOut) }
        return triageResult
    }

    func draft(_ prompt: AIPrompt, email: EmailInput, revision: String?) async throws -> DraftResult {
        prompts.append(prompt)
        if shouldThrow { throw URLError(.timedOut) }
        return DraftResult(body: draftBody)
    }

    func guardCheck(_ prompt: AIPrompt, email: EmailInput, matchedRules: [String]) async throws -> GuardAIResult {
        prompts.append(prompt)
        if shouldThrow { throw URLError(.timedOut) }
        return guardResult
    }

    func reminder(_ prompt: AIPrompt, text: String, now: Date) async throws -> ReminderParseResult {
        prompts.append(prompt)
        if shouldThrow { throw URLError(.timedOut) }
        return reminderResult
    }
}

/// Records every send. Used to prove nothing is sent during the undo window.
final class RecordingSender: DraftSending {
    private(set) var sentIDs: [String] = []
    var fail = false

    func sendDraft(id: String) async throws {
        if fail { throw URLError(.notConnectedToInternet) }
        sentIDs.append(id)
    }
}

enum Fixtures {
    private final class Token {}

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: Token.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return try Data(contentsOf: url)
    }

    static func container() throws -> ModelContainer {
        try ModelContainer(for: Schema(AgentryModels.all), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    static func email(_ subject: String = "Hello", body: String = "Can we meet tomorrow?", sender: String = "Ravi") -> EmailInput {
        EmailInput(sender: sender, senderAddress: "\(sender.lowercased())@example.com", subject: subject, body: body, receivedAt: .now)
    }
}

nonisolated struct EvalEmail: Codable {
    var sender: String
    var address: String
    var subject: String
    var body: String
    var html: String?
    var label: String?
    var jobStage: String?

    var input: EmailInput {
        EmailInput(sender: sender, senderAddress: address, subject: subject, body: body, receivedAt: .now)
    }
}
