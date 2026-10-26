import AppKit
import Foundation
import Observation
import SwiftData

/// Checks mail every few minutes and runs each new email through the pipeline:
/// Guard → Triage → Job tracker → (urgent / needs reply) Writer → notification.
@Observable
final class PollingService {
    private(set) var isChecking = false
    private(set) var lastCheck: Date?
    private(set) var lastError: String?
    private(set) var progress: (done: Int, total: Int)?

    private let context: ModelContext
    private let settings: AppSettings
    private let mail: () -> any MailProvider
    private let guardService: GuardService
    private let triage: TriageService
    private let writer: WriterService
    private let jobs: JobTracker
    private let notifications: NotificationService
    private let achievements: AchievementCenter

    private var loop: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    /// Called after each check with the number of new emails.
    var onChecked: ((Int) -> Void)?

    init(context: ModelContext, settings: AppSettings, mail: @escaping () -> any MailProvider, guardService: GuardService,
         triage: TriageService, writer: WriterService, jobs: JobTracker, notifications: NotificationService, achievements: AchievementCenter) {
        self.context = context
        self.settings = settings
        self.mail = mail
        self.guardService = guardService
        self.triage = triage
        self.writer = writer
        self.jobs = jobs
        self.notifications = notifications
        self.achievements = achievements
    }

    func start() {
        restart()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Catch up on mail missed while the Mac slept.
            MainActor.assumeIsolated { self?.checkNow() }
        }
    }

    /// Restart the timer (after the interval changes).
    func restart() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                let minutes = max(1, self?.settings.checkIntervalMinutes ?? 5)
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func checkNow() {
        Task { await check() }
    }

    func check() async {
        guard !isChecking else { return }
        let provider = mail()
        guard provider.isSignedIn else { return }
        isChecking = true
        lastError = nil
        defer {
            isChecking = false
            progress = nil
            lastCheck = .now
        }
        do {
            let fetched = try await provider.fetchNewMessages()
            let fresh = fetched.filter { !exists(gmailID: $0.gmailID) }
            if !fresh.isEmpty {
                ActivityEntry.log(context, "Fetched \(fresh.count) new email\(fresh.count == 1 ? "" : "s")", kind: .fetch)
            }
            progress = (0, fresh.count)
            for (i, item) in fresh.enumerated() {
                await process(item)
                progress = (i + 1, fresh.count)
            }
            try? context.save()
            onChecked?(fresh.count)
        } catch MailError.reauthRequired {
            lastError = MailError.reauthRequired.localizedDescription
        } catch {
            lastError = error.localizedDescription
            ActivityEntry.log(context, "Check failed", error.localizedDescription, kind: .error)
        }
    }

    private func exists(gmailID: String) -> Bool {
        var d = FetchDescriptor<Email>(predicate: #Predicate { $0.gmailID == gmailID })
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    private func isNewSender(_ address: String) -> Bool {
        var d = FetchDescriptor<Email>(predicate: #Predicate { $0.senderAddress == address })
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) == 0
    }

    /// The pipeline for one email.
    func process(_ item: FetchedEmail) async {
        let newSender = isNewSender(item.senderAddress)
        let email = Email(gmailID: item.gmailID, threadID: item.threadID, sender: item.senderName, senderAddress: item.senderAddress,
                          subject: item.subject, snippet: item.snippet, body: item.body, messageIDHeader: item.messageIDHeader,
                          receivedAt: item.receivedAt)
        context.insert(email)

        // 1. Guard
        let report = await guardService.check(email.input, html: item.html, isNewSender: newSender)
        email.guardVerdict = report.verdict
        email.guardReason = report.reason

        // 2. Triage
        do {
            let outcome = try await triage.triage(email.input)
            email.label = outcome.label
            email.reason = outcome.reason
            email.deadline = outcome.deadline
            email.isJobEmail = outcome.isJobEmail
            email.processedAt = .now
            ActivityEntry.log(context, "Labeled “\(email.subject)” as \(outcome.label.title)", outcome.reason, kind: .triage)

            // 3. Job tracker
            if outcome.isJobEmail, let stage = outcome.jobStage {
                let (app, change) = jobs.record(company: outcome.jobCompany, role: outcome.jobRole, stage: stage,
                                                subject: email.subject, at: email.receivedAt, in: context)
                switch change {
                case .added(let s):
                    ActivityEntry.log(context, "New job application: \(app.company)", "\(app.role.isEmpty ? "" : app.role + " · ")\(s.title)", kind: .job)
                case .moved(let from, let to):
                    ActivityEntry.log(context, "\(app.company) moved to \(to.title)", "Was \(from.title)", kind: .job)
                case .unchanged: break
                }
                if change != .unchanged {
                    if stage == .interview { achievements.record(.jobInterview(company: app.company)) }
                    if stage == .offer { achievements.record(.jobOffer(company: app.company)) }
                }
            }
        } catch {
            email.label = .fyi
            email.reason = "Couldn't triage: \(error.localizedDescription)"
            ActivityEntry.log(context, "Triage failed", error.localizedDescription, kind: .error)
        }

        // Flagged emails get a warning and no automatic draft.
        if report.verdict.isFlagged {
            ActivityEntry.log(context, "⚠️ Flagged “\(email.subject)”", report.reason, kind: .guardFlag)
            notifications.flagged(email)
            achievements.record(.threatBlocked)
            return
        }

        // 4. Writer
        guard let label = email.label, label.wantsDraft else { return }
        if settings.autoDraft {
            do {
                let draft = try await writer.createDraft(for: email, in: context)
                ActivityEntry.log(context, "Drafted a reply to \(email.sender)", email.subject, kind: .draft)
                if settings.notifyDrafts { notifications.draftReady(draft) }
            } catch {
                ActivityEntry.log(context, "Couldn't draft a reply", error.localizedDescription, kind: .error)
                if settings.notifyUrgent { notifications.importantEmail(email) }
            }
        } else if settings.notifyUrgent {
            notifications.importantEmail(email)
        }
    }
}
