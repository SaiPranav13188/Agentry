import Foundation
import Observation

enum MailMode: String, CaseIterable, Identifiable {
    case demo, appleMail, gmail
    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: "Demo inbox"
        case .appleMail: "Apple Mail"
        case .gmail: "Gmail (Google sign-in)"
        }
    }
}

/// User preferences, persisted in UserDefaults. Secrets (tokens) never live here; they go to the Keychain.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }
    var mailMode: MailMode { didSet { defaults.set(mailMode.rawValue, forKey: "mailMode") } }
    /// Public OAuth client ID (not a secret) from your Google Cloud project.
    var gmailClientID: String { didSet { defaults.set(gmailClientID, forKey: "gmailClientID") } }

    var aiPreference: AIPreference { didSet { defaults.set(aiPreference.rawValue, forKey: "aiPreference") } }
    var ollamaURL: String { didSet { defaults.set(ollamaURL, forKey: "ollamaURL") } }
    var ollamaModel: String { didSet { defaults.set(ollamaModel, forKey: "ollamaModel") } }

    /// Minutes between Gmail checks.
    var checkIntervalMinutes: Int { didSet { defaults.set(checkIntervalMinutes, forKey: "checkIntervalMinutes") } }
    /// Minutes after midnight for the morning briefing.
    var briefingMinuteOfDay: Int { didSet { defaults.set(briefingMinuteOfDay, forKey: "briefingMinuteOfDay") } }
    var morningBriefingEnabled: Bool { didSet { defaults.set(morningBriefingEnabled, forKey: "morningBriefingEnabled") } }

    var autoDraft: Bool { didSet { defaults.set(autoDraft, forKey: "autoDraft") } }
    var userName: String { didSet { defaults.set(userName, forKey: "userName") } }
    var signOff: String { didSet { defaults.set(signOff, forKey: "signOff") } }

    var notifyDrafts: Bool { didSet { defaults.set(notifyDrafts, forKey: "notifyDrafts") } }
    var notifyUrgent: Bool { didSet { defaults.set(notifyUrgent, forKey: "notifyUrgent") } }
    var notifyReminders: Bool { didSet { defaults.set(notifyReminders, forKey: "notifyReminders") } }

    var celebrationsEnabled: Bool { didSet { defaults.set(celebrationsEnabled, forKey: "celebrationsEnabled") } }
    var celebrationSound: Bool { didSet { defaults.set(celebrationSound, forKey: "celebrationSound") } }

    /// Last Gmail history ID we processed (not a secret).
    var lastHistoryID: String? { didSet { defaults.set(lastHistoryID, forKey: "lastHistoryID") } }
    var lastBriefingDay: String? { didSet { defaults.set(lastBriefingDay, forKey: "lastBriefingDay") } }
    /// Apple Mail mode: address to send from (empty = Mail's default account).
    var appleMailFromAddress: String { didSet { defaults.set(appleMailFromAddress, forKey: "appleMailFromAddress") } }
    /// Apple Mail mode: when we last read the inbox.
    var appleMailLastFetch: Date? { didSet { defaults.set(appleMailLastFetch, forKey: "appleMailLastFetch") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        mailMode = MailMode(rawValue: defaults.string(forKey: "mailMode") ?? "") ?? .demo
        gmailClientID = defaults.string(forKey: "gmailClientID") ?? ""
        aiPreference = AIPreference(rawValue: defaults.string(forKey: "aiPreference") ?? "") ?? .auto
        ollamaURL = defaults.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3.2:3b"
        checkIntervalMinutes = defaults.object(forKey: "checkIntervalMinutes") as? Int ?? 5
        briefingMinuteOfDay = defaults.object(forKey: "briefingMinuteOfDay") as? Int ?? 8 * 60
        morningBriefingEnabled = defaults.object(forKey: "morningBriefingEnabled") as? Bool ?? true
        autoDraft = defaults.object(forKey: "autoDraft") as? Bool ?? true
        userName = defaults.string(forKey: "userName") ?? NSFullUserName()
        signOff = defaults.string(forKey: "signOff") ?? "Best,"
        notifyDrafts = defaults.object(forKey: "notifyDrafts") as? Bool ?? true
        notifyUrgent = defaults.object(forKey: "notifyUrgent") as? Bool ?? true
        notifyReminders = defaults.object(forKey: "notifyReminders") as? Bool ?? true
        celebrationsEnabled = defaults.object(forKey: "celebrationsEnabled") as? Bool ?? true
        celebrationSound = defaults.object(forKey: "celebrationSound") as? Bool ?? true
        lastHistoryID = defaults.string(forKey: "lastHistoryID")
        lastBriefingDay = defaults.string(forKey: "lastBriefingDay")
        appleMailFromAddress = defaults.string(forKey: "appleMailFromAddress") ?? ""
        appleMailLastFetch = defaults.object(forKey: "appleMailLastFetch") as? Date
    }

    /// A Google OAuth client ID looks like `1234-abc.apps.googleusercontent.com` (not your email address).
    var gmailClientIDLooksValid: Bool {
        let id = gmailClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.hasSuffix(".apps.googleusercontent.com") && !id.contains("@") && !id.contains(" ")
    }

    var firstName: String {
        userName.split(separator: " ").first.map(String.init) ?? userName
    }

    var briefingTime: Date {
        get {
            Calendar.current.date(bySettingHour: briefingMinuteOfDay / 60, minute: briefingMinuteOfDay % 60, second: 0, of: .now) ?? .now
        }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            briefingMinuteOfDay = (c.hour ?? 8) * 60 + (c.minute ?? 0)
        }
    }
}
