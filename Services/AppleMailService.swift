import AppKit
import Foundation
import Observation

/// Uses the accounts already set up in macOS Mail (System Settings → Internet Accounts).
/// No Google Cloud project and no Google login inside Agentry.
///
/// Reading and sending go through Mail via JavaScript for Automation (`osascript`),
/// so the only permission needed is "Agentry wants to control Mail".
/// Drafts live in Agentry (Review screen); Mail only sends when SendService says so.
@Observable
final class AppleMailService: MailProvider, DraftSending {
    private let settings: AppSettings
    private(set) var lastError: String?
    private(set) var accountAddresses: [String] = []
    private var drafts: [String: StoredDraft]

    /// Mail message IDs already handed to the pipeline.
    private var seenIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "appleMail.seenIDs") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "appleMail.seenIDs") }
    }

    func resetSeen() { seenIDs = [] }

    nonisolated struct StoredDraft: Codable {
        var to: String
        var subject: String
        var body: String
    }

    init(settings: AppSettings) {
        self.settings = settings
        drafts = (try? JSONDecoder().decode([String: StoredDraft].self, from: Data(contentsOf: Self.draftsFile))) ?? [:]
    }

    /// Mail does the signing in; we're "connected" as long as Mail lets us talk to it.
    var isSignedIn: Bool { true }
    var accountEmail: String? { settings.appleMailFromAddress.isEmpty ? accountAddresses.first : settings.appleMailFromAddress }

    // MARK: - Reading

    func fetchNewMessages() async throws -> [FetchedEmail] {
        // Rolling 3-day window, so mail that Mail downloads late (e.g. right after adding an account)
        // is still picked up. Already-seen messages are skipped inside the script (no content fetched).
        let since = Date.now.addingTimeInterval(-3 * 86400)
        let seen = seenIDs
        let json = try await run(Self.fetchScript, args: [String(since.timeIntervalSince1970), "30", seen.joined(separator: ",")])
        let rows = try JSONDecoder().decode([MailRow].self, from: Data(json.utf8))
        settings.appleMailLastFetch = .now
        lastError = nil
        seenIDs = Array((seen + rows.map(\.id)).suffix(800))
        return rows.map { row in
            let from = MailText.parseAddress(row.sender)
            let body = MailText.clean(row.content)
            let messageID = row.messageId.isEmpty ? "" : "<\(row.messageId)>"
            return FetchedEmail(
                gmailID: "mail-\(row.id)",
                threadID: messageID,
                senderName: from.name,
                senderAddress: from.address,
                subject: row.subject.isEmpty ? "(no subject)" : row.subject,
                snippet: MailText.snippet(body),
                body: body,
                html: nil,
                messageIDHeader: messageID,
                receivedAt: Date(timeIntervalSince1970: row.date)
            )
        }
        .sorted { $0.receivedAt < $1.receivedAt }
    }

    func recentSentBodies(limit: Int) async throws -> [String] {
        let json = try await run(Self.sentScript, args: [String(limit + 3)])
        let bodies = try JSONDecoder().decode([String].self, from: Data(json.utf8))
        return Array(bodies.map(MailText.clean).filter { $0.count > 40 }.prefix(limit).map { MailText.trimForModel($0, maxChars: 450) })
    }

    /// Email addresses of the accounts in Mail (for "Send from").
    func refreshAccounts() async {
        do {
            let json = try await run(Self.accountsScript, args: [])
            accountAddresses = try JSONDecoder().decode([String].self, from: Data(json.utf8))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Drafts (kept by Agentry until you approve)

    func createDraft(reply: ReplyContext, body: String) async throws -> String {
        let id = "local-\(UUID().uuidString)"
        drafts[id] = StoredDraft(to: reply.to, subject: reply.replySubject, body: body)
        persist()
        return id
    }

    func updateDraft(id: String, reply: ReplyContext, body: String) async throws {
        drafts[id] = StoredDraft(to: reply.to, subject: reply.replySubject, body: body)
        persist()
    }

    func deleteDraft(id: String) async throws {
        drafts[id] = nil
        persist()
    }

    /// Only reachable through SendService (DraftSending).
    func sendDraft(id: String) async throws {
        guard let d = drafts[id] else { throw AppleMailError.draftMissing }
        _ = try await run(Self.sendScript, args: [d.to, d.subject, d.body, settings.appleMailFromAddress])
        drafts[id] = nil
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: Self.draftsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(drafts).write(to: Self.draftsFile, options: .atomic)
    }

    private static var draftsFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Agentry/mail_drafts.json")
    }

    // MARK: - Running scripts

    private func run(_ script: String, args: [String]) async throws -> String {
        do {
            return try await JXA.run(script, args: args)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    static func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    static func openInternetAccounts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
    }

    // MARK: - Scripts (JavaScript for Automation)

    private nonisolated struct MailRow: Decodable {
        var id: String
        var subject: String
        var sender: String
        var date: Double
        var messageId: String
        var content: String
    }

    private static let fetchScript = """
    function run(argv) {
      const Mail = Application('Mail');
      const since = new Date(parseFloat(argv[0]) * 1000);
      const limit = parseInt(argv[1]);
      const q = Mail.inbox.messages.whose({ dateReceived: { _greaterThan: since } });
      const seen = new Set((argv[2] || '').split(',').filter(x => x.length > 0));
      const ids = q.id();
      if (ids.length === 0) return '[]';
      const subjects = q.subject(), senders = q.sender(), dates = q.dateReceived(), mids = q.messageId();
      const order = ids.map((_, i) => i).filter(i => !seen.has(String(ids[i])))
        .sort((a, b) => dates[b] - dates[a]).slice(0, limit);
      return JSON.stringify(order.map(i => {
        let content = '';
        try { content = (q[i].content() || '').slice(0, 20000); } catch (e) {}
        return { id: String(ids[i]), subject: subjects[i] || '', sender: senders[i] || '',
                 date: dates[i].getTime() / 1000, messageId: mids[i] || '', content: content };
      }));
    }
    """

    private static let sentScript = """
    function run(argv) {
      const Mail = Application('Mail');
      const n = parseInt(argv[0]);
      const since = new Date(Date.now() - 30 * 86400 * 1000);
      let out = [];
      try {
        const q = Mail.sentMailbox.messages.whose({ dateSent: { _greaterThan: since } });
        const count = Math.min(q.length, n);
        for (let i = 0; i < count; i++) {
          try { out.push((q[i].content() || '').slice(0, 2000)); } catch (e) {}
        }
      } catch (e) {}
      return JSON.stringify(out);
    }
    """

    private static let accountsScript = """
    function run(argv) {
      const Mail = Application('Mail');
      const all = [];
      Mail.accounts().forEach(a => { try { (a.emailAddresses() || []).forEach(e => all.push(e)); } catch (e) {} });
      return JSON.stringify(all);
    }
    """

    private static let sendScript = """
    function run(argv) {
      const [to, subject, body, from] = argv;
      const Mail = Application('Mail');
      const msg = Mail.OutgoingMessage({ subject: subject, content: body, visible: false });
      Mail.outgoingMessages.push(msg);
      msg.toRecipients.push(Mail.Recipient({ address: to }));
      if (from && from.length > 0) { msg.sender = from; }
      msg.send();
      return 'sent';
    }
    """
}

enum AppleMailError: LocalizedError {
    case notAuthorized
    case draftMissing
    case script(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Agentry isn't allowed to control Mail. Turn it on in System Settings → Privacy & Security → Automation → Agentry → Mail."
        case .draftMissing:
            "This draft is no longer available. Reject it and draft the reply again."
        case .script(let message):
            "Mail: \(message)"
        }
    }
}

/// Runs a JavaScript for Automation script with `osascript` off the main thread.
nonisolated enum JXA {
    static func run(_ script: String, args: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", script] + args
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            // Read before waiting so large outputs can't fill the pipe and deadlock.
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let stderr = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                if stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not authorized") || stderr.localizedCaseInsensitiveContains("not allowed") {
                    throw AppleMailError.notAuthorized
                }
                let message = stderr.components(separatedBy: "execution error: ").last ?? stderr
                throw AppleMailError.script(message.isEmpty ? "Unknown error (\(process.terminationStatus))" : message)
            }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
