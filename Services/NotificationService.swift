import Foundation
import UserNotifications

/// Actions coming back from notification buttons.
enum NotificationAction {
    case sendDraft(draftUUID: String, approvalID: String, bodyHash: String)
    case editDraft(draftUUID: String)
    case rejectDraft(draftUUID: String)
    case undoSend(approvalID: String)
    case reminderDone(id: String)
    case reminderSnooze(id: String)
    case openEmail(gmailID: String)
    case openToday
    case signInAgain
}

/// Actionable macOS notifications.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private enum Category {
        static let draft = "DRAFT"
        static let reminder = "REMINDER"
        static let sending = "SENDING"
        static let email = "EMAIL"
        static let briefing = "BRIEFING"
        static let reauth = "REAUTH"
    }

    private var center: UNUserNotificationCenter? {
        // Unit tests run without an app bundle identifier.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    var onAction: ((NotificationAction) -> Void)?
    private(set) var authorized = false

    func setUp() {
        guard let center else { return }
        center.delegate = self
        let send = UNNotificationAction(identifier: "SEND", title: "Send", options: [])
        let edit = UNNotificationAction(identifier: "EDIT", title: "Edit", options: [.foreground])
        let reject = UNNotificationAction(identifier: "REJECT", title: "Reject", options: [.destructive])
        let undo = UNNotificationAction(identifier: "UNDO", title: "Undo", options: [])
        let done = UNNotificationAction(identifier: "DONE", title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "Snooze 1h", options: [])
        let signIn = UNNotificationAction(identifier: "SIGNIN", title: "Sign in again", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.draft, actions: [send, edit, reject], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.sending, actions: [undo], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.reminder, actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.email, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.briefing, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.reauth, actions: [signIn], intentIdentifiers: []),
        ])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return authorized
    }

    func refreshAuthorization() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private func post(id: String, title: String, subtitle: String = "", body: String, category: String, userInfo: [String: String] = [:], sound: Bool = true) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = userInfo
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: - Specific notifications

    func draftReady(_ draft: Draft) {
        guard let email = draft.email else { return }
        let label = email.effectiveLabel == .urgent ? "🔥 Urgent · " : ""
        post(
            id: "draft-\(draft.uuid)",
            title: "\(label)\(email.sender)",
            subtitle: email.subject,
            body: "\(email.reason)\n\nDraft: \(MailText.snippet(draft.body, length: 160))",
            category: Category.draft,
            userInfo: ["draft": draft.uuid, "approval": draft.approvalID, "hash": draft.bodyHash]
        )
    }

    func importantEmail(_ email: Email) {
        post(id: "email-\(email.gmailID)", title: "\(email.effectiveLabel == .urgent ? "🔥 " : "")\(email.sender)",
             subtitle: email.subject, body: email.reason, category: Category.email, userInfo: ["email": email.gmailID])
    }

    func flagged(_ email: Email) {
        post(id: "flag-\(email.gmailID)", title: "⚠️ Suspicious email blocked", subtitle: email.sender,
             body: "\(email.subject)\n\(email.guardReason) No draft was written.", category: Category.email, userInfo: ["email": email.gmailID])
    }

    func sending(_ item: SendService.PendingSend, seconds: Int) {
        post(id: "sending-\(item.id)", title: "Sending in \(seconds)s…", body: item.summary, category: Category.sending,
             userInfo: ["approval": item.id], sound: false)
    }

    func sent(_ draft: Draft) {
        post(id: "sending-\(draft.approvalID)", title: "Sent ✓", body: draft.email.map { "Reply to \($0.sender)" } ?? "Reply sent",
             category: Category.email, sound: false)
    }

    func message(title: String, body: String) {
        post(id: UUID().uuidString, title: title, body: body, category: Category.email)
    }

    func reminder(_ reminder: Reminder) {
        let id = reminder.uuid
        post(id: "reminder-\(id)", title: reminder.status == .late ? "⏰ Late reminder" : "⏰ Reminder",
             body: reminder.text + (reminder.status == .late ? "\n(Was due \(reminder.dueAt.formatted(date: .abbreviated, time: .shortened)))" : ""),
             category: Category.reminder, userInfo: ["reminder": id])
    }

    func briefing(title: String, body: String) {
        post(id: "briefing-\(Date.now.formatted(.iso8601.year().month().day()))", title: title, body: body, category: Category.briefing)
    }

    func reauthRequired() {
        post(id: "reauth", title: "Sign in to Gmail again", body: "Google's test-mode login expires every 7 days. Click to sign in again.",
             category: Category.reauth)
    }

    // MARK: - Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let category = response.notification.request.content.categoryIdentifier
        let actionID = response.actionIdentifier
        let draft = info["draft"] as? String ?? ""
        let approval = info["approval"] as? String ?? ""
        let hash = info["hash"] as? String ?? ""
        let reminder = info["reminder"] as? String ?? ""
        let email = info["email"] as? String ?? ""

        let action: NotificationAction? = switch (category, actionID) {
        case (Category.draft, "SEND"): .sendDraft(draftUUID: draft, approvalID: approval, bodyHash: hash)
        case (Category.draft, "REJECT"): .rejectDraft(draftUUID: draft)
        case (Category.draft, _): .editDraft(draftUUID: draft)
        case (Category.sending, "UNDO"): .undoSend(approvalID: approval)
        case (Category.reminder, "DONE"): .reminderDone(id: reminder)
        case (Category.reminder, "SNOOZE"): .reminderSnooze(id: reminder)
        case (Category.reauth, _): .signInAgain
        case (Category.briefing, _): .openToday
        case (_, UNNotificationDefaultActionIdentifier) where !email.isEmpty: .openEmail(gmailID: email)
        default: nil
        }
        guard let action else { return }
        await MainActor.run { self.onAction?(action) }
    }
}
