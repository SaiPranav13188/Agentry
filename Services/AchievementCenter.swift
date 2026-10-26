import AppKit
import Foundation
import Observation

enum Pet: String, CaseIterable, Sendable {
    case cat, dog
}

struct Celebration: Identifiable, Equatable {
    enum Size { case big, small }

    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var pet: Pet
    var size: Size
    /// True the first time an achievement unlocks.
    var isUnlock: Bool
}

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let pet: Pet
}

enum AchievementEvent {
    case draftSent(total: Int)
    case inboxZero
    case reviewQueueCleared
    case reminderDone
    case threatBlocked
    case jobInterview(company: String)
    case jobOffer(company: String)
    case signedIn
}

/// Tracks achievements and queues the cat & dog celebrations.
@Observable
final class AchievementCenter {
    static let all: [Achievement] = [
        Achievement(id: "first-send", title: "First Reply Sent", detail: "Approved and sent your first AI draft.", symbol: "paperplane.fill", pet: .cat),
        Achievement(id: "ten-sends", title: "Reply Machine", detail: "Sent 10 replies with Agentry.", symbol: "bolt.fill", pet: .dog),
        Achievement(id: "fifty-sends", title: "Inbox Whisperer", detail: "Sent 50 replies with Agentry.", symbol: "crown.fill", pet: .cat),
        Achievement(id: "inbox-zero", title: "Inbox Zero", detail: "Cleared every email that needed you.", symbol: "sparkles", pet: .dog),
        Achievement(id: "review-clear", title: "Clean Sweep", detail: "Reviewed every waiting draft.", symbol: "checkmark.seal.fill", pet: .cat),
        Achievement(id: "reminder-done", title: "Promise Keeper", detail: "Finished your first reminder.", symbol: "bell.badge.fill", pet: .cat),
        Achievement(id: "guard-dog", title: "Guard Dog", detail: "Blocked a suspicious email.", symbol: "shield.lefthalf.filled", pet: .dog),
        Achievement(id: "interview", title: "Interview Unlocked", detail: "Landed a job interview.", symbol: "person.2.wave.2.fill", pet: .cat),
        Achievement(id: "offer", title: "Offer Letter!", detail: "Got a job offer. Huge!", symbol: "party.popper.fill", pet: .dog),
        Achievement(id: "connected", title: "All Set Up", detail: "Connected your inbox to Agentry.", symbol: "link", pet: .dog),
    ]

    private let defaults: UserDefaults
    private let settings: AppSettings
    private(set) var unlocked: Set<String>
    private(set) var queue: [Celebration] = []
    var current: Celebration? { queue.first }

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        unlocked = Set(defaults.stringArray(forKey: "achievements.unlocked") ?? [])
    }

    func record(_ event: AchievementEvent) {
        switch event {
        case .draftSent(let total):
            if unlock("first-send") { return }
            if total >= 10, unlock("ten-sends") { return }
            if total >= 50, unlock("fifty-sends") { return }
            celebrate(Celebration(title: "Sent!", subtitle: Self.sentLines.randomElement()!, symbol: "paperplane.fill",
                                  pet: Bool.random() ? .cat : .dog, size: .small, isUnlock: false))
        case .inboxZero:
            if unlock("inbox-zero") { return }
            celebrate(Celebration(title: "Inbox Zero", subtitle: "Nothing needs you right now. Go stretch!", symbol: "sparkles",
                                  pet: .dog, size: .big, isUnlock: false))
        case .reviewQueueCleared:
            if unlock("review-clear") { return }
            celebrate(Celebration(title: "Review queue clear", subtitle: "Every draft handled.", symbol: "checkmark.seal.fill",
                                  pet: .cat, size: .small, isUnlock: false))
        case .reminderDone:
            if unlock("reminder-done") { return }
            celebrate(Celebration(title: "Done!", subtitle: "One less thing on your mind.", symbol: "checkmark.circle.fill",
                                  pet: .cat, size: .small, isUnlock: false))
        case .threatBlocked:
            unlock("guard-dog")
        case .jobInterview(let company):
            if unlock("interview") { return }
            celebrate(Celebration(title: "Interview with \(company)!", subtitle: "You've got this.", symbol: "person.2.wave.2.fill",
                                  pet: .cat, size: .big, isUnlock: false))
        case .jobOffer(let company):
            unlock("offer")
            celebrate(Celebration(title: "Offer from \(company)! 🎉", subtitle: "All that hard work paid off.", symbol: "party.popper.fill",
                                  pet: .dog, size: .big, isUnlock: false))
        case .signedIn:
            unlock("connected")
        }
    }

    /// Unlocks if new. Returns true when a celebration was queued.
    @discardableResult
    private func unlock(_ id: String) -> Bool {
        guard !unlocked.contains(id), let a = Self.all.first(where: { $0.id == id }) else { return false }
        unlocked.insert(id)
        defaults.set(Array(unlocked), forKey: "achievements.unlocked")
        celebrate(Celebration(title: a.title, subtitle: a.detail, symbol: a.symbol, pet: a.pet, size: .big, isUnlock: true))
        return true
    }

    func celebrate(_ c: Celebration) {
        guard settings.celebrationsEnabled else { return }
        // Don't stack more than three.
        guard queue.count < 3 else { return }
        queue.append(c)
        if queue.count == 1 { playSound(for: c) }
    }

    func dismissCurrent() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        if let next = queue.first { playSound(for: next) }
    }

    func preview(_ pet: Pet) {
        celebrate(Celebration(title: pet == .cat ? "Meow-velous!" : "Pawsome work!", subtitle: "This is how Agentry celebrates your wins.",
                              symbol: "star.fill", pet: pet, size: .big, isUnlock: false))
    }

    func resetAchievements() {
        unlocked = []
        defaults.removeObject(forKey: "achievements.unlocked")
    }

    private func playSound(for c: Celebration) {
        guard settings.celebrationSound else { return }
        NSSound(named: c.size == .big ? "Hero" : "Glass")?.play()
    }

    private static let sentLines = [
        "Off it goes. 📬", "Another one done!", "Smooth.", "Reply delivered with style.", "That's how it's done.",
    ]

    // MARK: - Your own cat & dog videos

    /// Drop .mp4/.mov files into ~/Library/Application Support/Agentry/Celebrations/{cats,dogs}
    /// and they play instead of the drawn animation.
    static var mediaFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Agentry/Celebrations", isDirectory: true)
    }

    static func ensureMediaFolders() {
        for sub in ["cats", "dogs"] {
            try? FileManager.default.createDirectory(at: mediaFolder.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
    }

    static func randomVideo(for pet: Pet) -> URL? {
        let folder = mediaFolder.appendingPathComponent(pet == .cat ? "cats" : "dogs")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }.randomElement()
    }
}
