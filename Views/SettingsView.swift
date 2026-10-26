import AppKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Query private var emails: [Email]
    @Query private var drafts: [Draft]
    @State private var confirmSwitch: MailMode?
    @State private var confirmWipe = false

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            account(settings)
            ai(settings)

            Section("Schedule") {
                Picker("Check Gmail every", selection: $settings.checkIntervalMinutes) {
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
                .onChange(of: settings.checkIntervalMinutes) { app.polling.restart() }
                Toggle("Morning briefing notification", isOn: $settings.morningBriefingEnabled)
                DatePicker("Briefing time", selection: Binding(get: { settings.briefingTime }, set: { settings.briefingTime = $0 }), displayedComponents: .hourAndMinute)
                    .disabled(!settings.morningBriefingEnabled)
                Toggle("Open Agentry when you log in", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
            }

            Section {
                Toggle("Write drafts automatically for urgent and needs-reply emails", isOn: $settings.autoDraft)
                TextField("Your name", text: $settings.userName)
                TextField("Sign-off", text: $settings.signOff, prompt: Text("Best,"))
            } header: {
                Text("Drafts")
            } footer: {
                Label("AI can only create drafts. Sending always needs your click plus a 30-second undo window.", systemImage: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                if !app.notifications.authorized {
                    HStack {
                        Label("Notifications are off for Agentry", systemImage: "bell.slash.fill").foregroundStyle(.orange)
                        Spacer()
                        Button("Allow") { Task { await app.notifications.requestAuthorization() } }
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
                Toggle("Draft ready (with Send / Edit / Reject)", isOn: $settings.notifyDrafts)
                Toggle("Urgent emails", isOn: $settings.notifyUrgent)
                Toggle("Reminders (with Done / Snooze 1h)", isOn: $settings.notifyReminders)
                Button("Send a test notification") {
                    app.notifications.message(title: "Hello from Agentry 👋", body: "Notifications are working.")
                }
            }

            celebrations(settings)
            evaluation

            Section("Data") {
                Button("Erase local Agentry data…", role: .destructive) { confirmWipe = true }
                Text("Emails, drafts, reminders, jobs and activity stored on this Mac. Your Gmail is not touched.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .confirmationDialog("Switch inbox?", isPresented: Binding(get: { confirmSwitch != nil }, set: { if !$0 { confirmSwitch = nil } })) {
            Button("Switch to \(confirmSwitch?.title ?? "")") {
                if let mode = confirmSwitch { app.switchMode(to: mode) }
            }
        } message: {
            Text("Agentry's local data (labels, drafts, reminders, jobs) is cleared so demo and real mail never mix.")
        }
        .confirmationDialog("Erase all local data?", isPresented: $confirmWipe) {
            Button("Erase", role: .destructive) {
                app.wipeLocalData()
                app.settings.lastHistoryID = nil
                app.polling.checkNow()
            }
        }
        .task { await app.notifications.refreshAuthorization() }
    }

    // MARK: Sections

    @ViewBuilder
    private func account(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section {
            Picker("Inbox", selection: Binding(get: { settings.mailMode }, set: { confirmSwitch = $0 })) {
                Text("Demo").tag(MailMode.demo)
                Text("Apple Mail").tag(MailMode.appleMail)
                Text("Gmail sign-in").tag(MailMode.gmail)
            }
            .pickerStyle(.segmented)

            switch settings.mailMode {
            case .demo:
                Text("Sample emails only. Nothing real is read or sent.")
                    .foregroundStyle(.secondary)
            case .appleMail:
                appleMailRows(settings)
            case .gmail:
                gmailRows(settings)
            }
        } header: {
            Text("Account")
        } footer: {
            Group {
                switch settings.mailMode {
                case .demo:
                    Text("Switch to Apple Mail to use your real Gmail without any Google sign-in in Agentry.")
                case .appleMail:
                    Text("Agentry uses the accounts in the Mail app. Add Gmail once in System Settings → Internet Accounts, then allow Agentry to control Mail when asked. Drafts stay in Agentry until you click Send; Mail sends them.")
                case .gmail:
                    Text("Needs a free Google Cloud OAuth client of type iOS (bundle ID com.saipranav.Agentry). Tokens are stored in the Keychain; Google asks you to sign in again about every 7 days in Testing mode.")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func appleMailRows(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        HStack {
            if let error = app.appleMail.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            } else if app.appleMail.accountAddresses.isEmpty {
                Text("Not checked yet").foregroundStyle(.secondary)
            } else {
                Label("Connected to Mail · \(app.appleMail.accountAddresses.count) account(s)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
            Button("Check connection") { Task { await app.connectAppleMail() } }
        }
        Picker("Send from", selection: $settings.appleMailFromAddress) {
            Text("Mail's default account").tag("")
            ForEach(app.appleMail.accountAddresses, id: \.self) { Text($0).tag($0) }
            if !settings.appleMailFromAddress.isEmpty && !app.appleMail.accountAddresses.contains(settings.appleMailFromAddress) {
                Text(settings.appleMailFromAddress).tag(settings.appleMailFromAddress)
            }
        }
        HStack {
            Button("Add Gmail to Mail…") { AppleMailService.openInternetAccounts() }
            Button("Automation permission…") { AppleMailService.openAutomationSettings() }
        }
        .task { if app.appleMail.accountAddresses.isEmpty { await app.appleMail.refreshAccounts() } }
    }

    @ViewBuilder
    private func gmailRows(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        TextField("Google OAuth client ID", text: $settings.gmailClientID, prompt: Text("1234-abc.apps.googleusercontent.com"))
            .font(.system(size: 12, design: .monospaced))
        ClientIDHint(clientID: settings.gmailClientID, valid: settings.gmailClientIDLooksValid)
        HStack {
            if app.gmail.isSignedIn {
                Label(app.gmail.accountEmail ?? "Signed in", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Sign out") { app.signOut() }
            } else {
                if app.gmail.needsReauth {
                    Label("Login expired", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Text("Not signed in").foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await app.signIn() }
                } label: {
                    if app.signingIn { ProgressView().controlSize(.small) } else { Text(app.gmail.needsReauth ? "Sign in again" : "Sign in with Google") }
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(!settings.gmailClientIDLooksValid || app.signingIn)
            }
        }
    }

    @ViewBuilder
    private func ai(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section {
            Picker("AI model", selection: $settings.aiPreference) {
                ForEach(AIPreference.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Active now") {
                HStack(spacing: 6) {
                    Circle().fill(app.ai.kind == .basic ? Color.orange : .green).frame(width: 7, height: 7)
                    Text(app.ai.kind.title)
                }
            }
            LabeledContent("Apple Intelligence") {
                Text(app.ai.appleStatus).foregroundStyle(app.ai.appleAvailable ? .green : .secondary)
            }
            LabeledContent("Ollama") {
                Text(app.ai.ollamaAvailable ? "Running · \(app.ai.ollamaModels.count) model(s)" : "Not running")
                    .foregroundStyle(app.ai.ollamaAvailable ? .green : .secondary)
            }
            TextField("Ollama URL", text: $settings.ollamaURL)
            if app.ai.ollamaModels.isEmpty {
                TextField("Ollama model", text: $settings.ollamaModel)
            } else {
                Picker("Ollama model", selection: $settings.ollamaModel) {
                    ForEach(app.ai.ollamaModels, id: \.self) { Text($0).tag($0) }
                    if !app.ai.ollamaModels.contains(settings.ollamaModel) { Text(settings.ollamaModel).tag(settings.ollamaModel) }
                }
            }
            Button("Re-check AI availability") { Task { await app.ai.refreshAvailability() } }
        } header: {
            Text("AI (free, on your Mac)")
        } footer: {
            Text("Automatic uses Apple's on-device model when available, otherwise Ollama (`brew install ollama && ollama pull llama3.2:3b`), otherwise simple rules. Nothing leaves your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func celebrations(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section {
            Toggle("Celebrate wins with cats & dogs", isOn: $settings.celebrationsEnabled)
            Toggle("Play a sound", isOn: $settings.celebrationSound)
                .disabled(!settings.celebrationsEnabled)
            HStack {
                Button("Preview cat 🐱") { app.achievements.preview(.cat) }
                Button("Preview dog 🐶") { app.achievements.preview(.dog) }
                Spacer()
                Button("Open videos folder") {
                    AchievementCenter.ensureMediaFolders()
                    NSWorkspace.shared.open(AchievementCenter.mediaFolder)
                }
            }
            .disabled(!settings.celebrationsEnabled)
            AchievementGrid(unlocked: app.achievements.unlocked)
        } header: {
            Text("Celebrations")
        } footer: {
            Text("Drop your own .mp4 or .mov clips into the cats or dogs folder and Agentry plays them instead of the drawn animation. Animations follow Reduce Motion.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var evaluation: some View {
        let labeled = emails.filter { $0.userLabel != nil && $0.label != nil }
        let accuracy = EvalMetrics.triageAccuracy(labeled.map { ($0.label, $0.userLabel!) })
        let sent = drafts.filter { $0.status == .sent }
        let rejected = drafts.filter { $0.status == .rejected }.count
        let shown = sent.count + rejected
        let acceptance = EvalMetrics.draftAcceptance(sentUnedited: sent.filter { !$0.wasEdited }.count,
                                                     sentEdited: sent.filter(\.wasEdited).count, rejected: rejected)
        let flagged = emails.filter(\.isFlagged).count

        return Section {
            LabeledContent("Triage accuracy") {
                HStack(spacing: 8) {
                    Text(accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "—").fontWeight(.semibold)
                        .foregroundStyle((accuracy ?? 1) >= 0.85 ? .green : .orange)
                    Text("on \(labeled.count) labeled · target > 85%").foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(Double(labeled.count), 100), total: 100) {
                Text("Label ~100 emails with right-click → Correct label (or keys 1–4 in the Inbox)").font(.system(size: 11))
            }
            LabeledContent("Draft acceptance") {
                HStack(spacing: 8) {
                    Text(acceptance.map { "\(Int(($0 * 100).rounded()))%" } ?? "—").fontWeight(.semibold)
                    Text("sent without edits ÷ drafts handled (\(shown))").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Guard") {
                Text("\(flagged) email\(flagged == 1 ? "" : "s") flagged").foregroundStyle(.secondary)
            }
        } header: {
            Text("Evaluation")
        } footer: {
            Text("Run the full evals (triage, injection detection, backend comparison) with ⌘U in Xcode. See README.md.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AchievementGrid: View {
    let unlocked: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(AchievementCenter.all) { a in
                let has = unlocked.contains(a.id)
                VStack(spacing: 4) {
                    Image(systemName: has ? a.symbol : "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(has ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                    Text(a.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(has ? 0.06 : 0.025)))
                .help(a.detail)
                .opacity(has ? 1 : 0.6)
            }
        }
        .padding(.vertical, 4)
    }
}
