import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftData

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, review, inbox, reminders, jobs, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .review: "Review"
        case .inbox: "Inbox"
        case .reminders: "Reminders"
        case .jobs: "Jobs"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .review: "checkmark.bubble.fill"
        case .inbox: "tray.fill"
        case .reminders: "bell.fill"
        case .jobs: "briefcase.fill"
        case .activity: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }

    var shortcut: Character {
        Character(String((AppSection.allCases.firstIndex(of: self) ?? 0) + 1))
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var symbol: String = "checkmark.circle.fill"
    var isError = false
}

/// Wires the services together and holds UI state shared across windows.
@Observable
final class AppState {
    static let shared = AppState()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    let settings: AppSettings
    let ai: AIService
    let gmail: GmailService
    let appleMail: AppleMailService
    private(set) var demo = DemoMailService()
    let notifications = NotificationService()
    let achievements: AchievementCenter
    let briefing = BriefingService()
    let jobs = JobTracker()

    let triage: TriageService
    let writer: WriterService
    let guardService: GuardService
    let reminders: ReminderService
    let sendService: SendService
    let polling: PollingService

    // UI state
    var section: AppSection = .today
    var inboxFilter: InboxFilter = .all
    var selectedDraftUUID: String?
    var selectedEmailID: String?
    var showCommandPalette = false
    var showShortcuts = false
    var toast: Toast?
    var signingIn = false
    var revisingDraftUUIDs: Set<String> = []
    var syncingDraftUUIDs: Set<String> = []
    var launchAtLogin = false

    /// Set by the menu bar label so non-view code can open the main window.
    var openMainWindow: (() -> Void)?

    private var tickTask: Task<Void, Never>?
    private var started = false

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// ~/Library/Application Support/Agentry/Agentry.store
    static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Agentry", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Agentry.store")
    }

    init(inMemory: Bool = AppState.isRunningTests || UserDefaults.standard.bool(forKey: "AgentryInMemory")) {
        let schema = Schema(AgentryModels.all)
        let config = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: AppState.storeURL)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A broken store shouldn't brick the app: fall back to memory and tell the user.
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }

        let settings = AppSettings()
        self.settings = settings
        ai = AIService(settings: settings)
        gmail = GmailService(settings: settings)
        appleMail = AppleMailService(settings: settings)
        achievements = AchievementCenter(settings: settings)

        triage = TriageService(ai: ai, userName: { settings.userName })
        guardService = GuardService(ai: ai)
        reminders = ReminderService(ai: ai)

        // Late-bound closures so switching demo ⇄ Gmail takes effect everywhere.
        var mailRef: () -> any MailProvider = { fatalError() }
        var senderRef: () -> any DraftSending = { fatalError() }
        writer = WriterService(ai: ai, mail: { mailRef() }, settings: settings)
        sendService = SendService(sender: { senderRef() })
        polling = PollingService(
            context: container.mainContext, settings: settings, mail: { mailRef() }, guardService: guardService,
            triage: triage, writer: writer, jobs: jobs, notifications: notifications, achievements: achievements
        )
        mailRef = { [unowned self] in self.mail }
        senderRef = { [unowned self] in self.draftSender }

        wireCallbacks()
    }

    /// The active mail account (demo or Gmail).
    var mail: any MailProvider {
        switch settings.mailMode {
        case .demo: demo
        case .appleMail: appleMail
        case .gmail: gmail
        }
    }

    private var draftSender: any DraftSending {
        switch settings.mailMode {
        case .demo: demo
        case .appleMail: appleMail
        case .gmail: gmail
        }
    }

    /// Account line for the sidebar and menu bar.
    var accountLabel: String {
        switch settings.mailMode {
        case .demo: "Demo inbox"
        case .appleMail: appleMail.accountEmail ?? "Apple Mail"
        case .gmail: gmail.accountEmail ?? "Not connected"
        }
    }

    /// Ask Mail for its accounts (this triggers the "control Mail" permission prompt the first time).
    @discardableResult
    func connectAppleMail() async -> Bool {
        await appleMail.refreshAccounts()
        if let error = appleMail.lastError {
            showToast(error, symbol: "exclamationmark.triangle.fill", isError: true)
            return false
        }
        if appleMail.accountAddresses.isEmpty {
            showToast("Mail has no accounts yet. Add Gmail in System Settings → Internet Accounts.", symbol: "envelope.badge.person.crop", isError: true)
            return false
        }
        return true
    }

    var isConnected: Bool { mail.isSignedIn }

    // MARK: - Lifecycle

    func start() {
        guard !started, !Self.isRunningTests else { return }
        started = true
        notifications.setUp()
        AchievementCenter.ensureMediaFolders()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Task {
            await ai.refreshAvailability()
            await notifications.refreshAuthorization()
            if settings.hasOnboarded { polling.start() }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        expireOldDrafts()
        #if DEBUG
        // Launch argument for demos/screenshots: -AgentryStartSection review
        if let start = UserDefaults.standard.string(forKey: "AgentryStartSection"), let s = AppSection(rawValue: start) {
            section = s
        }
        if let pet = UserDefaults.standard.string(forKey: "AgentryPreviewCelebration").flatMap(Pet.init(rawValue:)) {
            Task {
                try? await Task.sleep(for: .seconds(2))
                achievements.preview(pet)
            }
        }
        #endif
    }

    func finishOnboarding(mode: MailMode) {
        settings.mailMode = mode
        settings.hasOnboarded = true
        if mode == .demo { seedDemoExtras() }
        polling.start()
        section = .today
    }

    private func wireCallbacks() {
        notifications.onAction = { [weak self] action in self?.handle(action) }
        gmail.onReauthRequired = { [weak self] in
            self?.notifications.reauthRequired()
            self?.log("Google login expired", "Sign in again from Settings.", kind: .error)
        }

        sendService.onSent = { [weak self] draft in
            guard let self else { return }
            draft.email?.isDone = true
            log("Sent reply to \(draft.email?.sender ?? "someone")", draft.email?.subject ?? "", kind: .send)
            notifications.remove(id: "draft-\(draft.uuid)")
            if !NSApp.isActive { notifications.sent(draft) }
            let total = sentCount()
            achievements.record(.draftSent(total: total))
            save()
            checkMilestones()
        }
        sendService.onFailed = { [weak self] draft, error in
            self?.log("Send stopped", error.localizedDescription, kind: .error)
            self?.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true)
            self?.save()
        }
        sendService.onUndone = { [weak self] draft in
            self?.log("Undid send", draft.email?.subject ?? "", kind: .system)
            self?.showToast("Send cancelled", symbol: "arrow.uturn.backward.circle.fill")
            self?.save()
        }
    }

    // MARK: - Every 30 seconds: reminders + morning briefing

    func tick(now: Date = .now) {
        let delivered = reminders.deliverDue(in: context, now: now)
        for r in delivered {
            if settings.notifyReminders { notifications.reminder(r) }
            log(r.status == .late ? "Late reminder: \(r.text)" : "Reminder: \(r.text)", kind: .reminder)
        }
        if !delivered.isEmpty { save() }

        guard settings.morningBriefingEnabled, settings.hasOnboarded else { return }
        let today = now.formatted(.iso8601.year().month().day())
        let cal = Calendar.current
        let minuteNow = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        if settings.lastBriefingDay != today, minuteNow >= settings.briefingMinuteOfDay, minuteNow < 23 * 60 {
            settings.lastBriefingDay = today
            let b = briefing.make(context: context, name: settings.firstName, now: now)
            notifications.briefing(title: "☀️ \(b.greeting)", body: briefing.notificationBody(b))
            // Show Today next time you look, but never yank you away mid-task.
            if !NSApp.isActive { section = .today }
        }
    }

    private func expireOldDrafts() {
        let pending = DraftStatus.pending.rawValue
        let drafts = (try? context.fetch(FetchDescriptor<Draft>(predicate: #Predicate { $0.statusRaw == pending }))) ?? []
        for d in drafts where d.expiresAt < .now {
            // Drafts stay reviewable; they just need a fresh approval when you look again.
            d.issueApproval()
        }
        save()
    }

    // MARK: - Drafts

    func draft(uuid: String) -> Draft? {
        var d = FetchDescriptor<Draft>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func email(gmailID: String) -> Email? {
        var d = FetchDescriptor<Email>(predicate: #Predicate { $0.gmailID == gmailID })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// You clicked Send in the Review screen. `shownBody` is exactly what was on screen.
    func send(_ draft: Draft, shownBody: String) async {
        guard draft.status == .pending else { return }
        if shownBody != draft.body {
            draft.applyEdit(shownBody)
            await sync(draft)
        }
        do {
            let item = try sendService.requestSend(draft, approvalID: draft.approvalID, presentedHash: Draft.hash(shownBody))
            log("Approved reply to \(draft.email?.sender ?? "someone")", "Sending after the \(Int(sendService.undoWindow))s undo window.", kind: .send)
            if !NSApp.isActive { notifications.sending(item, seconds: Int(sendService.undoWindow)) }
            save()
        } catch {
            showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    func reject(_ draft: Draft) {
        guard draft.status == .pending else { return }
        draft.status = .rejected
        notifications.remove(id: "draft-\(draft.uuid)")
        log("Rejected draft", draft.email?.subject ?? "", kind: .reject)
        save()
        Task {
            try? await writer.discardDraft(draft)
        }
        checkMilestones()
    }

    /// Your typing in the editor. Issues a new approval and syncs to Gmail.
    func applyEdit(_ draft: Draft, body: String) async {
        guard draft.status == .pending, body != draft.body else { return }
        draft.applyEdit(body)
        log("Edited draft", draft.email?.subject ?? "", kind: .draft)
        await sync(draft)
    }

    private func sync(_ draft: Draft) async {
        syncingDraftUUIDs.insert(draft.uuid)
        defer { syncingDraftUUIDs.remove(draft.uuid) }
        do {
            try await writer.syncDraft(draft)
        } catch {
            showToast("Couldn't update Gmail draft: \(error.localizedDescription)", symbol: "exclamationmark.icloud.fill", isError: true)
        }
        save()
    }

    /// "Ask AI to change…"
    func revise(_ draft: Draft, instruction: String) async {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, draft.status == .pending else { return }
        revisingDraftUUIDs.insert(draft.uuid)
        defer { revisingDraftUUIDs.remove(draft.uuid) }
        do {
            let revised = try await writer.revise(draft, instruction: text)
            draft.applyEdit(revised)
            log("AI revised draft", "“\(text)”", kind: .draft)
            await sync(draft)
        } catch {
            showToast("Couldn't revise: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    /// Write a draft on demand (for emails without one).
    func draftReply(for email: Email) async {
        if let existing = email.pendingDraft {
            openReview(existing)
            return
        }
        do {
            let draft = try await writer.createDraft(for: email, in: context)
            log("Drafted a reply to \(email.sender)", email.subject, kind: .draft)
            save()
            openReview(draft)
        } catch {
            showToast("Couldn't write a draft: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    func openReview(_ draft: Draft) {
        withMotion { section = .review }
        selectedDraftUUID = draft.uuid
        bringToFront()
    }

    // MARK: - Inbox

    func toggleDone(_ email: Email) {
        withMotion { email.isDone.toggle() }
        save()
        if email.isDone { checkMilestones() }
    }

    func correctLabel(_ email: Email, to label: EmailLabel?) {
        withMotion { email.userLabel = label }
        if let label {
            log("Corrected label", "“\(email.subject)” → \(label.title)", kind: .triage)
        }
        save()
        if settings.mailMode != .demo { EvalMetrics.exportLabels(from: context) }
    }

    /// Celebrate inbox zero / clean review queue when you get there.
    private func checkMilestones() {
        let pendingRaw = DraftStatus.pending.rawValue
        let sendingRaw = DraftStatus.sending.rawValue
        let pendingDrafts = (try? context.fetchCount(FetchDescriptor<Draft>(predicate: #Predicate { $0.statusRaw == pendingRaw || $0.statusRaw == sendingRaw }))) ?? 0
        let emails = (try? context.fetch(FetchDescriptor<Email>(predicate: #Predicate { $0.isDone == false }))) ?? []
        let needsYou = emails.filter { !$0.isFlagged && ($0.effectiveLabel == .urgent || $0.effectiveLabel == .needsReply) }.count
        if pendingDrafts == 0, needsYou == 0 {
            achievements.record(.inboxZero)
        } else if pendingDrafts == 0 {
            achievements.record(.reviewQueueCleared)
        }
    }

    private func sentCount() -> Int {
        let sent = DraftStatus.sent.rawValue
        return (try? context.fetchCount(FetchDescriptor<Draft>(predicate: #Predicate { $0.statusRaw == sent }))) ?? 0
    }

    // MARK: - Reminders

    func saveReminder(_ parsed: ParsedReminder) {
        context.insert(Reminder(text: parsed.text, dueAt: parsed.dueAt, recurrence: parsed.recurrence))
        log("Added reminder: \(parsed.text)", parsed.dueAt.formatted(date: .abbreviated, time: .shortened), kind: .reminder)
        save()
        showToast("Reminder set for \(parsed.dueAt.formatted(.relative(presentation: .named)))", symbol: "bell.badge.fill")
    }

    func completeReminder(_ reminder: Reminder) {
        withMotion { reminders.markDone(reminder, in: context) }
        notifications.remove(id: "reminder-\(reminder.uuid)")
        log("Finished reminder: \(reminder.text)", kind: .reminder)
        achievements.record(.reminderDone)
        save()
    }

    func snoozeReminder(_ reminder: Reminder) {
        withMotion { reminders.snooze(reminder) }
        notifications.remove(id: "reminder-\(reminder.uuid)")
        log("Snoozed reminder 1h: \(reminder.text)", kind: .reminder)
        save()
    }

    private func reminder(uuid: String) -> Reminder? {
        var d = FetchDescriptor<Reminder>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    // MARK: - Notifications

    func handle(_ action: NotificationAction) {
        switch action {
        case .sendDraft(let uuid, let approvalID, let hash):
            guard let draft = draft(uuid: uuid) else { return }
            do {
                let item = try sendService.requestSend(draft, approvalID: approvalID, presentedHash: hash)
                log("Approved reply from notification", draft.email?.subject ?? "", kind: .send)
                notifications.sending(item, seconds: Int(sendService.undoWindow))
                save()
            } catch {
                notifications.message(title: "Not sent", body: "\(error.localizedDescription) Open Agentry to review it.")
            }
        case .editDraft(let uuid):
            if let draft = draft(uuid: uuid) { openReview(draft) }
        case .rejectDraft(let uuid):
            if let draft = draft(uuid: uuid) { reject(draft) }
        case .undoSend(let approvalID):
            sendService.undo(approvalID: approvalID)
        case .reminderDone(let id):
            if let r = reminder(uuid: id) { completeReminder(r) }
        case .reminderSnooze(let id):
            if let r = reminder(uuid: id) { snoozeReminder(r) }
        case .openEmail(let id):
            section = .inbox
            selectedEmailID = id
            bringToFront()
        case .openToday:
            section = .today
            bringToFront()
        case .signInAgain:
            section = .settings
            bringToFront()
            Task { await signIn() }
        }
    }

    func bringToFront() {
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Account

    func signIn() async {
        signingIn = true
        defer { signingIn = false }
        do {
            try await gmail.signIn()
            if settings.mailMode != .gmail { switchMode(to: .gmail) }
            log("Signed in to Gmail", gmail.accountEmail ?? "", kind: .system)
            achievements.record(.signedIn)
            showToast("Connected \(gmail.accountEmail ?? "Gmail")", symbol: "checkmark.seal.fill")
            polling.restart()
        } catch {
            if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession" { return }
            showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    func signOut() {
        gmail.signOut()
        log("Signed out of Gmail", kind: .system)
    }

    /// Demo and Gmail data never mix: switching clears local data (your Gmail is untouched).
    func switchMode(to mode: MailMode) {
        guard mode != settings.mailMode else { return }
        polling.stop()
        wipeLocalData()
        settings.mailMode = mode
        settings.lastHistoryID = nil
        settings.appleMailLastFetch = nil
        appleMail.resetSeen()
        if mode == .demo {
            demo = DemoMailService()
            seedDemoExtras()
        }
        log(mode == .demo ? "Switched to the demo inbox" : "Switched to Gmail", kind: .system)
        save()
        polling.restart()
    }

    func wipeLocalData() {
        for p in sendService.pending { sendService.undo(approvalID: p.id) }
        try? context.delete(model: Draft.self)
        try? context.delete(model: Email.self)
        try? context.delete(model: Reminder.self)
        try? context.delete(model: JobApplication.self)
        try? context.delete(model: ActivityEntry.self)
        appleMail.resetSeen()
        save()
    }

    private func seedDemoExtras() {
        let cal = Calendar.current
        let tomorrow10 = cal.date(bySettingHour: 10, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: .now)!)!
        context.insert(Reminder(text: "Pay the electricity bill", dueAt: tomorrow10))
        context.insert(Reminder(text: "Stretch and drink water", dueAt: .now.addingTimeInterval(45 * 60), recurrence: .daily))
        context.insert(JobApplication(company: "Bluepeak", role: "Software Engineer I", stage: .applied, lastUpdate: .now.addingTimeInterval(-5 * 86400)))
        save()
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            showToast("Couldn't change login item: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    // MARK: - Helpers

    func log(_ event: String, _ details: String = "", kind: ActivityKind = .system) {
        ActivityEntry.log(context, event, details, kind: kind)
    }

    func save() {
        try? context.save()
    }

    func showToast(_ message: String, symbol: String = "checkmark.circle.fill", isError: Bool = false) {
        let t = Toast(message: message, symbol: symbol, isError: isError)
        withMotion(Motion.bouncy) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(isError ? 4.5 : 2.8))
            if toast?.id == t.id { withMotion { toast = nil } }
        }
    }
}
