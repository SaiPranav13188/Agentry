import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security

/// Gmail over REST: OAuth login (PKCE, no client secret), fetch new mail via history IDs,
/// and draft management. Scopes: gmail.readonly + gmail.compose.
@Observable
final class GmailService: NSObject, MailProvider, DraftSending {
    static let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.compose",
    ]
    private static let api = "https://gmail.googleapis.com/gmail/v1/users/me/"

    private let settings: AppSettings
    private(set) var accountEmail: String?
    private(set) var needsReauth = false
    private var tokens: OAuthTokens?
    private var authSession: ASWebAuthenticationSession?

    /// Called once when Google says the login expired (Testing mode: about every 7 days).
    var onReauthRequired: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        tokens = Keychain.load(OAuthTokens.self, key: "gmail.tokens")
        accountEmail = tokens?.email
    }

    var isSignedIn: Bool { tokens?.refreshToken != nil && !needsReauth }

    // MARK: - OAuth

    private var clientID: String { settings.gmailClientID.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Google's iOS/macOS clients use the reversed client ID as the redirect scheme.
    private var redirectScheme: String {
        let prefix = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    private var redirectURI: String { "\(redirectScheme):/oauthredirect" }

    func signIn() async throws {
        guard !clientID.isEmpty else { throw MailError.notConfigured }
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !clientID.contains("@") else { throw MailError.invalidClientID }
        let verifier = PKCE.verifier()
        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: redirectScheme) { url, error in
                if let url { continuation.resume(returning: url) } else {
                    continuation.resume(throwing: error ?? MailError.badResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            session.start()
        }
        authSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw MailError.badResponse }

        let response = try await tokenRequest([
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refresh = response.refresh_token else { throw MailError.badResponse }
        var newTokens = OAuthTokens(
            accessToken: response.access_token,
            refreshToken: refresh,
            expiresAt: .now.addingTimeInterval(TimeInterval(response.expires_in ?? 3600) - 60)
        )
        tokens = newTokens
        needsReauth = false

        let profile: GmailProfile = try await get("profile")
        newTokens.email = profile.emailAddress
        tokens = newTokens
        accountEmail = profile.emailAddress
        settings.lastHistoryID = nil
        Keychain.save(newTokens, key: "gmail.tokens")
    }

    func signOut() {
        tokens = nil
        accountEmail = nil
        needsReauth = false
        settings.lastHistoryID = nil
        Keychain.delete(key: "gmail.tokens")
    }

    private func accessToken() async throws -> String {
        guard var current = tokens, let refresh = current.refreshToken else { throw MailError.notSignedIn }
        if needsReauth { throw MailError.reauthRequired }
        if current.expiresAt > .now { return current.accessToken }
        do {
            let r = try await tokenRequest([
                "client_id": clientID,
                "refresh_token": refresh,
                "grant_type": "refresh_token",
            ])
            current.accessToken = r.access_token
            current.expiresAt = .now.addingTimeInterval(TimeInterval(r.expires_in ?? 3600) - 60)
            tokens = current
            Keychain.save(current, key: "gmail.tokens")
            return current.accessToken
        } catch MailError.http(400, _), MailError.http(401, _) {
            markReauthRequired()
            throw MailError.reauthRequired
        }
    }

    private func markReauthRequired() {
        guard !needsReauth else { return }
        needsReauth = true
        onReauthRequired?()
    }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw MailError.http(code, String(decoding: data, as: UTF8.self)) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - REST

    private func send(_ path: String, method: String = "GET", json: [String: Any]? = nil, retry: Bool = true) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.api + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401, retry {
            tokens?.expiresAt = .distantPast
            return try await send(path, method: method, json: json, retry: false)
        }
        if code == 401 { markReauthRequired(); throw MailError.reauthRequired }
        guard (200..<300).contains(code) else {
            throw MailError.http(code, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send(path))
    }

    // MARK: - Fetching

    func fetchNewMessages() async throws -> [FetchedEmail] {
        var ids: [String] = []
        if let start = settings.lastHistoryID {
            do {
                var pageToken: String?
                repeat {
                    var path = "history?startHistoryId=\(start)&historyTypes=messageAdded&labelId=INBOX"
                    if let pageToken { path += "&pageToken=\(pageToken)" }
                    let page: HistoryList = try await get(path)
                    for h in page.history ?? [] {
                        for added in h.messagesAdded ?? [] where !ids.contains(added.message.id) {
                            ids.append(added.message.id)
                        }
                    }
                    if let latest = page.historyId { settings.lastHistoryID = latest }
                    pageToken = page.nextPageToken
                } while pageToken != nil
            } catch MailError.http(404, _) {
                // History too old (Mac was off for a long time): catch up with a time query.
                ids = try await listIDs(query: "in:inbox newer_than:2d", max: 30)
                settings.lastHistoryID = try await (get("profile") as GmailProfile).historyId
            }
        } else {
            ids = try await listIDs(query: "in:inbox newer_than:3d", max: 25)
            settings.lastHistoryID = try await (get("profile") as GmailProfile).historyId
        }

        var result: [FetchedEmail] = []
        for id in ids {
            if let message = try? await fetchMessage(id: id) { result.append(message) }
        }
        return result.sorted { $0.receivedAt < $1.receivedAt }
    }

    private func listIDs(query: String, max: Int) async throws -> [String] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let list: MessageList = try await get("messages?q=\(q)&maxResults=\(max)")
        return (list.messages ?? []).map(\.id)
    }

    private func fetchMessage(id: String) async throws -> FetchedEmail {
        let m: GmailMessage = try await get("messages/\(id)?format=full")
        let headers = m.payload?.allHeaders ?? [:]
        let from = MailText.parseAddress(headers["from"] ?? "")
        var plain: String?
        var html: String?
        m.payload?.collectBodies(plain: &plain, html: &html)
        let raw = plain ?? html.map(MailText.htmlToText) ?? m.snippet ?? ""
        let body = MailText.clean(raw)
        let received = Date(timeIntervalSince1970: (Double(m.internalDate ?? "") ?? Date.now.timeIntervalSince1970 * 1000) / 1000)
        return FetchedEmail(
            gmailID: m.id,
            threadID: m.threadId,
            senderName: from.name,
            senderAddress: from.address,
            subject: headers["subject"] ?? "(no subject)",
            snippet: MailText.snippet(body.isEmpty ? (m.snippet ?? "") : body),
            body: body,
            html: html,
            messageIDHeader: headers["message-id"] ?? "",
            receivedAt: received
        )
    }

    func recentSentBodies(limit: Int) async throws -> [String] {
        let ids = try await listIDs(query: "in:sent", max: 6)
        var bodies: [String] = []
        for id in ids where bodies.count < limit {
            if let m = try? await fetchMessage(id: id), m.body.count > 40 {
                bodies.append(MailText.trimForModel(m.body, maxChars: 450))
            }
        }
        return bodies
    }

    // MARK: - Drafts

    func createDraft(reply: ReplyContext, body: String) async throws -> String {
        let data = try await send("drafts", method: "POST", json: ["message": ["raw": MIME.reply(reply, body: body), "threadId": reply.threadID]])
        return try JSONDecoder().decode(GmailDraft.self, from: data).id
    }

    func updateDraft(id: String, reply: ReplyContext, body: String) async throws {
        _ = try await send("drafts/\(id)", method: "PUT", json: ["id": id, "message": ["raw": MIME.reply(reply, body: body), "threadId": reply.threadID]])
    }

    func deleteDraft(id: String) async throws {
        _ = try await send("drafts/\(id)", method: "DELETE")
    }

    /// Only reachable through SendService (DraftSending).
    func sendDraft(id: String) async throws {
        _ = try await send("drafts/send", method: "POST", json: ["id": id])
    }
}

extension GmailService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor()
    }
}

// MARK: - MIME

nonisolated enum MIME {
    static func reply(_ reply: ReplyContext, body: String) -> String {
        var headers = [
            "To: \(reply.to)",
            "Subject: \(encodeHeader(reply.replySubject))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=\"UTF-8\"",
            "Content-Transfer-Encoding: 8bit",
        ]
        if !reply.inReplyTo.isEmpty {
            headers.append("In-Reply-To: \(reply.inReplyTo)")
            headers.append("References: \(reply.inReplyTo)")
        }
        let raw = headers.joined(separator: "\r\n") + "\r\n\r\n" + body.replacingOccurrences(of: "\n", with: "\r\n")
        return Data(raw.utf8).base64URLEncoded
    }

    static func encodeHeader(_ value: String) -> String {
        value.allSatisfy(\.isASCII) ? value : "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }
}

// MARK: - Keychain

nonisolated enum Keychain {
    private static let service = "com.saipranav.Agentry"

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - PKCE + wire types

nonisolated enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

nonisolated struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var email: String?
}

private nonisolated struct TokenResponse: Decodable {
    var access_token: String
    var refresh_token: String?
    var expires_in: Int?
}

private nonisolated struct GmailProfile: Decodable {
    var emailAddress: String
    var historyId: String
}

private nonisolated struct MessageList: Decodable {
    struct Ref: Decodable { var id: String }
    var messages: [Ref]?
}

private nonisolated struct HistoryList: Decodable {
    struct Added: Decodable { var message: MessageList.Ref }
    struct Item: Decodable { var messagesAdded: [Added]? }
    var history: [Item]?
    var historyId: String?
    var nextPageToken: String?
}

private nonisolated struct GmailDraft: Decodable { var id: String }

private nonisolated struct GmailMessage: Decodable {
    var id: String
    var threadId: String
    var snippet: String?
    var internalDate: String?
    var payload: Part?

    final class Part: Decodable {
        struct Header: Decodable { var name: String; var value: String }
        struct Body: Decodable { var data: String? }
        var mimeType: String?
        var headers: [Header]?
        var body: Body?
        var parts: [Part]?

        var allHeaders: [String: String] {
            Dictionary((headers ?? []).map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        }

        func collectBodies(plain: inout String?, html: inout String?) {
            if let data = body?.data, let decoded = Data(base64URLEncoded: data).map({ String(decoding: $0, as: UTF8.self) }) {
                if mimeType == "text/plain", plain == nil { plain = decoded }
                if mimeType == "text/html", html == nil { html = decoded }
            }
            for part in parts ?? [] { part.collectBodies(plain: &plain, html: &html) }
        }
    }
}

nonisolated extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}

private nonisolated extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
