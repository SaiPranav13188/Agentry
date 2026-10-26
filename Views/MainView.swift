import SwiftData
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if app.settings.hasOnboarded {
                content
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: app.settings.hasOnboarded)
    }

    private var content: some View {
        @Bindable var app = app
        return NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ZStack {
                Theme.windowBackground.ignoresSafeArea()
                detail
                    .id(app.section)
                    .transition(.opacity)
            }
            .animation(Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: app.section)
            .toolbar { toolbar }
        }
        .overlay(alignment: .bottom) { UndoBarStack() }
        .overlay(alignment: .top) {
            if let toast = app.toast {
                ToastView(toast: toast)
                    .padding(.top, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .overlay {
            if app.showCommandPalette {
                CommandPalette()
                    .transition(.opacity)
            }
        }
        .overlay { CelebrationOverlay() }
        .sheet(isPresented: $app.showShortcuts) { ShortcutsSheet() }
        .background {
            // "?" opens the shortcut list.
            Button("") { app.showShortcuts = true }
                .keyboardShortcut("/", modifiers: .shift)
                .hidden()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.section {
        case .today: TodayView()
        case .review: ReviewView()
        case .inbox: InboxView()
        case .reminders: RemindersView()
        case .jobs: JobsView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            CheckNowButton()
            Button {
                withMotion(Motion.quick) { app.showCommandPalette.toggle() }
            } label: {
                Label("Command palette", systemImage: "command")
            }
            .help("Command palette (⌘K)")
        }
    }
}

struct CheckNowButton: View {
    @Environment(AppState.self) private var app
    @State private var spin = false

    var body: some View {
        Button {
            app.polling.checkNow()
        } label: {
            if app.polling.isChecking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    if let p = app.polling.progress, p.total > 0 {
                        Text("\(p.done)/\(p.total)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                }
            } else {
                Label("Check now", systemImage: "arrow.clockwise")
            }
        }
        .disabled(app.polling.isChecking || !app.isConnected)
        .help(helpText)
    }

    private var helpText: String {
        if let error = app.polling.lastError { return "Last check failed: \(error)" }
        if let last = app.polling.lastCheck { return "Checked \(last.formatted(.relative(presentation: .named))) · ⌘R" }
        return "Check for new mail (⌘R)"
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<Draft> { $0.statusRaw == "pending" || $0.statusRaw == "sending" }) private var drafts: [Draft]
    @Query(filter: #Predicate<Email> { $0.isDone == false }) private var openEmails: [Email]
    @Query(filter: #Predicate<Reminder> { $0.statusRaw != "done" }) private var openReminders: [Reminder]

    var body: some View {
        @Bindable var app = app
        List(selection: Binding<AppSection?>(get: { app.section }, set: { if let s = $0 { app.section = s } })) {
            Section {
                ForEach([AppSection.today, .review, .inbox], id: \.self) { row($0) }
            }
            Section("Organize") {
                ForEach([AppSection.reminders, .jobs, .activity], id: \.self) { row($0) }
            }
            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { brand }
        .safeAreaInset(edge: .bottom) { AccountFooter() }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.brand)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            Text("Agentry").font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
            Button {
                withMotion(Motion.quick) { app.showCommandPalette = true }
            } label: {
                KeyCap("⌘K")
            }
            .buttonStyle(.plain)
            .help("Command palette")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .review: drafts.count
        case .inbox: openEmails.filter { $0.effectiveLabel == .urgent && !$0.isFlagged }.count
        case .reminders: openReminders.filter { $0.status == .fired || $0.status == .late }.count
        default: 0
        }
    }

    private func row(_ section: AppSection) -> some View {
        let count = badge(for: section)
        return Label {
            HStack {
                Text(section.title)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(section == .review ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.red.opacity(0.85))))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .motion(Motion.bouncy, value: count)
        } icon: {
            Image(systemName: section.symbol)
        }
        .tag(section)
    }
}

private struct AccountFooter: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: app.settings.userName.isEmpty ? "You" : app.settings.userName, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.accountLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(app.ai.kind == .basic ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(app.ai.kind.shortTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture { withMotion { app.section = .settings } }
        .help("Account and AI settings")
    }
}
