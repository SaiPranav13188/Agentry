import Foundation

/// A message fetched from the mail provider, already cleaned to plain text.
nonisolated struct FetchedEmail: Sendable, Equatable {
    var gmailID: String
    var threadID: String
    var senderName: String
    var senderAddress: String
    var subject: String
    var snippet: String
    /// Clean plain text: latest message only, no quoted replies or signature.
    var body: String
    /// Original HTML (if any). Only used by GuardService; never stored.
    var html: String?
    var messageIDHeader: String
    var receivedAt: Date
}

/// What a reply draft needs to know about the email it answers.
nonisolated struct ReplyContext: Sendable {
    var to: String
    var subject: String
    var threadID: String
    var inReplyTo: String

    var replySubject: String {
        subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }
}

/// Reading mail and managing drafts. AI code may use this; it cannot send.
protocol MailProvider: AnyObject {
    var isSignedIn: Bool { get }
    var accountEmail: String? { get }
    func fetchNewMessages() async throws -> [FetchedEmail]
    /// Bodies of a few recent sent emails (used as style examples).
    func recentSentBodies(limit: Int) async throws -> [String]
    func createDraft(reply: ReplyContext, body: String) async throws -> String
    func updateDraft(id: String, reply: ReplyContext, body: String) async throws
    func deleteDraft(id: String) async throws
}

/// The one capability that sends mail. Only SendService holds a reference to it.
protocol DraftSending: AnyObject {
    func sendDraft(id: String) async throws
}

enum MailError: LocalizedError {
    case notConfigured
    case invalidClientID
    case notSignedIn
    case reauthRequired
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Add your Google OAuth client ID in Settings first."
        case .invalidClientID: "That doesn't look like an OAuth client ID. It should end in .apps.googleusercontent.com (see README)."
        case .notSignedIn: "You're not signed in to Gmail."
        case .reauthRequired: "Your Google login expired. Please sign in again."
        case .http(let code, let message): "Gmail error \(code): \(message)"
        case .badResponse: "Gmail returned something unexpected."
        }
    }
}

extension Email {
    var replyContext: ReplyContext {
        ReplyContext(to: senderAddress, subject: subject, threadID: threadID, inReplyTo: messageIDHeader)
    }
}

/// Plain-text helpers for email bodies.
nonisolated enum MailText {
    /// Convert HTML to readable text.
    static func htmlToText(_ html: String) -> String {
        var s = html
        for tag in ["style", "script", "head"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</(p|div|tr|li|h[1-6])>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&rsquo;": "’", "&lsquo;": "‘", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }

    /// Keep only the latest message: drop quoted replies, forwarded history, and signatures.
    static func clean(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var kept: [String] = []
        let lines = normalized.components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // Quoted reply header ("On Mon, 3 Mar 2026 at 10:00, Ravi <r@x.com> wrote:")
            if line.range(of: "^On .{4,200}wrote:$", options: .regularExpression) != nil { break }
            if line.hasPrefix("On "), index + 1 < lines.count,
               (line + " " + lines[index + 1]).range(of: "^On .{4,200}wrote:\\s*$", options: .regularExpression) != nil { break }
            if line.range(of: "^-{2,}\\s*(Original|Forwarded) Message\\s*-{2,}$", options: [.regularExpression, .caseInsensitive]) != nil { break }
            if line.hasPrefix("________________________________") { break }
            if !kept.isEmpty, line.range(of: "^From: .+", options: .regularExpression) != nil,
               index + 1 < lines.count, lines[index + 1].hasPrefix("Sent:") || lines[index + 1].hasPrefix("Date:") { break }
            // Signatures
            if line == "--" || line == "-- " || raw == "-- " { break }
            if line.range(of: "^(Sent from my|Get Outlook for|Sent via)", options: [.regularExpression, .caseInsensitive]) != nil { break }
            if line.hasPrefix(">") { continue }
            kept.append(raw.trimmingCharacters(in: .whitespaces))
        }
        var result = kept.joined(separator: "\n")
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cap text for the small on-device context window, keeping the start.
    static func trimForModel(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)) + "\n[…trimmed]"
    }

    static func snippet(_ text: String, length: Int = 140) -> String {
        let flat = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return flat.count > length ? String(flat.prefix(length)) + "…" : flat
    }

    /// Parse `Name <addr@x.com>` into (name, address).
    static func parseAddress(_ header: String) -> (name: String, address: String) {
        if let open = header.lastIndex(of: "<"), let close = header.lastIndex(of: ">"), open < close {
            let address = String(header[header.index(after: open)..<close])
            var name = String(header[..<open]).trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? address : name, address)
        }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        return (trimmed, trimmed)
    }
}
