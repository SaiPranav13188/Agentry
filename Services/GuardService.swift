import Foundation

nonisolated struct GuardReport: Sendable, Equatable {
    var verdict: GuardVerdict
    var reason: String
    var matchedRules: [String]
    var usedAI: Bool
}

/// AI part 3: pattern rules first, one AI check only when something looks off.
final class GuardService {
    private let ai: any AIBackend

    init(ai: any AIBackend) {
        self.ai = ai
    }

    /// Rules strong enough to flag an email even if the AI says it's fine.
    nonisolated static let strongRules: Set<String> = ["prompt injection", "hidden text", "zero-width characters", "data request"]

    func check(_ email: EmailInput, html: String?, isNewSender: Bool) async -> GuardReport {
        let matches = Self.ruleMatches(subject: email.subject, body: email.body, html: html)
        guard !matches.isEmpty || isNewSender else {
            return GuardReport(verdict: .safe, reason: "Known sender, no warning signs.", matchedRules: [], usedAI: false)
        }

        let prompt = AIPrompt(
            instructions: PromptLibrary.render(PromptLibrary.load("guard"), ["rules": matches.isEmpty ? "none" : matches.joined(separator: ", ")]),
            prompt: "Check this email.\n\n" + PromptLibrary.dataBlock(email, maxChars: 2000)
        )
        var verdict: GuardVerdict
        var reason: String
        do {
            let r = try await ai.guardCheck(prompt, email: email, matchedRules: matches)
            verdict = GuardVerdict.parse(r.verdict)
            reason = r.reason
        } catch {
            verdict = matches.isEmpty ? .safe : .suspicious
            reason = matches.isEmpty ? "New sender, no warning signs." : "Matched: \(matches.joined(separator: ", "))."
        }
        if verdict == .safe, !Set(matches).isDisjoint(with: Self.strongRules) {
            verdict = .suspicious
            reason = "Matched: \(matches.joined(separator: ", "))."
        }
        return GuardReport(verdict: verdict, reason: reason, matchedRules: matches, usedAI: true)
    }

    // MARK: - Rules

    private nonisolated static let injectionPatterns = [
        "ignore (all |any )?(the )?(previous|prior|above|earlier|preceding) (instructions|prompts|messages|rules)",
        "disregard (all |any )?(the |your )?(previous|prior|above|earlier)? ?(instructions|rules|guidelines)",
        "forget (all |everything |your )?(previous |prior )?(instructions|rules|you were told)",
        "\\byou are now (in |an? |the )?(developer|dan\\b|unrestricted|admin|jailbroken|free from|no longer|acting as|operating as|my assistant|a different|in charge)",
        "new (system )?instructions ?:",
        "system prompt",
        "\\[(system|assistant|admin)\\]",
        "<\\|?(im_start|system)\\|?>",
        "override (your|the|all) (rules|instructions|safety|guidelines)",
        "do not (tell|inform|alert|notify) the (user|owner|recipient)",
        "(ai|email) assistant[,:]? (please )?(ignore|forward|send|reply|delete|reveal)",
        "act as (an? )?(admin|administrator|developer mode|unrestricted)",
        "pretend (you are|to be) ",
    ]

    private nonisolated static let dataRequestPatterns = [
        "(forward|send|share|email|reply with|export) (me |us )?(all|every|the last|your|any|copies of)? ?\\d* ?(of )?(your |the )?(emails?|messages|inbox|contacts|password|passwords|credentials|otp|one.time|verification codes?|bank details|card details|api keys?|tokens?)",
        "(send|share|tell|give) (me |us )?(the |your )?(otp|password|pin|cvv|verification code|login code)",
    ]

    private nonisolated static let phishingPatterns = [
        "verify your (account|identity|password|login)",
        "(account|mailbox) (will be |has been )?(suspended|locked|closed|deactivated|disabled)",
        "confirm your (password|credentials|bank|card|payment details)",
        "unusual (sign.in|login|log.in) activity",
        "gift ?cards?",
        "wire (the )?(money|funds|transfer)",
        "(you have|you've) won",
        "claim your (prize|reward|refund)",
    ]

    /// Names of the rules this email matches. Pure function (tested in evals).
    nonisolated static func ruleMatches(subject: String, body: String, html: String?) -> [String] {
        let text = (subject + "\n" + body + "\n" + (html.map(MailText.htmlToText) ?? "")).lowercased()
        var hits: [String] = []

        if injectionPatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            hits.append("prompt injection")
        }
        // Zero-width characters hidden inside words ("ig\u{200B}nore") are used to dodge filters.
        // (Newsletters pad preheaders with them between spaces; that's fine.)
        if (body + " " + (html ?? "")).range(of: "\\p{L}[\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}]+\\p{L}", options: .regularExpression) != nil {
            hits.append("zero-width characters")
        }
        if let html, hasHiddenText(html) {
            hits.append("hidden text")
        }
        if dataRequestPatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            hits.append("data request")
        }
        if let html, hasMismatchedLink(html) {
            hits.append("mismatched link")
        }
        if phishingPatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            hits.append("phishing language")
        }
        return hits
    }

    /// Hidden HTML (display:none, zero font size, white text…) that contains instruction-like words.
    /// Plain hidden preheaders in newsletters don't count.
    nonisolated static func hasHiddenText(_ html: String) -> Bool {
        let hiddenStyle = "(display:\\s*none|visibility:\\s*hidden|font-size:\\s*[01](px|pt)?\\s*[;\"']|opacity:\\s*0(\\.0+)?\\s*[;\"']|color:\\s*(#fff(fff)?|white)\\s*[;\"']|max-height:\\s*0)"
        let pattern = "<(\\w+)[^>]*style\\s*=\\s*[\"'][^\"']*\(hiddenStyle)[^>]*>([\\s\\S]*?)</\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let suspicious = ["assistant", "ai ", "instruction", "ignore", "forward", "send", "reply", "password", "otp", "code",
                          "credential", "system", "prompt", "override", "export", "contacts", "inbox", "approve"]
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(match.range(at: match.numberOfRanges - 1), in: html) else { continue }
            let inner = MailText.htmlToText(String(html[r])).lowercased()
            if suspicious.contains(where: { inner.contains($0) }) { return true }
        }
        return false
    }

    /// A link whose visible text is a URL/domain different from where it really points.
    nonisolated static func hasMismatchedLink(_ html: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return false }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let hrefRange = Range(match.range(at: 1), in: html), let textRange = Range(match.range(at: 2), in: html) else { continue }
            let href = String(html[hrefRange])
            let text = MailText.htmlToText(String(html[textRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let shownHost = host(of: text), let realHost = host(of: href) else { continue }
            if !realHost.hasSuffix(shownHost) && !shownHost.hasSuffix(realHost) { return true }
        }
        return false
    }

    private nonisolated static func host(of string: String) -> String? {
        let s = string.lowercased()
        guard s.range(of: "^(https?://)?[a-z0-9-]+(\\.[a-z0-9-]+)+(/\\S*)?$", options: .regularExpression) != nil else { return nil }
        let withScheme = s.hasPrefix("http") ? s : "https://" + s
        guard let host = URL(string: withScheme)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
