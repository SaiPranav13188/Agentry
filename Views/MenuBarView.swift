import SwiftData
import SwiftUI

/// Menu bar icon with a badge for drafts waiting.
struct MenuBarLabel: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Draft> { $0.statusRaw == "pending" }) private var drafts: [Draft]

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: drafts.isEmpty ? "envelope.badge.shield.half.filled" : "envelope.badge.shield.half.filled.fill")
            if !drafts.isEmpty {
                Text("\(drafts.count)")
            }
        }
        .onAppear {
            app.openMainWindow = { openWindow(id: "main") }
        }
    }
}

/// Small popover: urgent emails, drafts waiting, next reminder, "Open Agentry".
struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Draft> { $0.statusRaw == "pending" }, sort: \Draft.createdAt, order: .reverse) private var drafts: [Draft]
    @Query(filter: #Predicate<Email> { $0.isDone == false }, sort: \Email.receivedAt, order: .reverse) private var openEmails: [Email]
    @Query(filter: #Predicate<Reminder> { $0.statusRaw != "done" }, sort: \Reminder.dueAt) private var reminders: [Reminder]

    var body: some View {
        let urgent = openEmails.filter { $0.effectiveLabel == .urgent && !$0.isFlagged }
        VStack(alignment: .leading, spacing: 12) {
            header

            if !app.settings.hasOnboarded {
                Text("Open Agentry to finish setting up.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else if urgent.isEmpty && drafts.isEmpty {
                HStack(spacing: 10) {
                    PetView(pet: .dog, mood: .idle).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All caught up").font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("Nothing urgent, no drafts waiting.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !drafts.isEmpty {
                block("Drafts waiting", symbol: "checkmark.bubble.fill", color: Theme.brandColor, count: drafts.count) {
                    ForEach(drafts.prefix(3)) { draft in
                        MiniRow(name: draft.email?.sender ?? "", title: draft.email?.subject ?? "", trailing: "Review") {
                            app.selectedDraftUUID = draft.uuid
                            app.section = .review
                            open()
                        }
                    }
                }
            }

            if !urgent.isEmpty {
                block("Urgent", symbol: "flame.fill", color: .red, count: urgent.count) {
                    ForEach(urgent.prefix(3)) { email in
                        MiniRow(name: email.sender, title: email.subject, trailing: email.receivedAt.mailStyle) {
                            app.selectedEmailID = email.gmailID
                            app.section = .inbox
                            open()
                        }
                    }
                }
            }

            if let next = reminders.first {
                block("Next reminder", symbol: "bell.fill", color: .orange, count: nil) {
                    HStack {
                        Text(next.text).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer()
                        Text(next.dueAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11))
                            .foregroundStyle(next.status == .late ? .red : .secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button {
                    app.polling.checkNow()
                } label: {
                    if app.polling.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check now", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(SubtleButtonStyle())
                .disabled(app.polling.isChecking)

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button {
                    open()
                } label: {
                    Text("Open Agentry")
                }
                .buttonStyle(BrandButtonStyle())
                .keyboardShortcut("o")
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.brand)
                Image(systemName: "envelope.badge.shield.half.filled").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Agentry").font(.system(size: 14, weight: .bold, design: .rounded))
                Text(statusLine).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusLine: String {
        if app.polling.isChecking { return "Checking mail…" }
        if let error = app.polling.lastError { return error }
        if let last = app.polling.lastCheck { return "Checked \(last.formatted(.relative(presentation: .named)))" }
        return app.accountLabel
    }

    private func block<Content: View>(_ title: String, symbol: String, color: Color, count: Int?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title, symbol: symbol, count: count, color: color)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func open() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }
}

private struct MiniRow: View {
    let name: String
    let title: String
    let trailing: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Avatar(name: name, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(trailing).font(.system(size: 11, weight: .medium)).foregroundStyle(hovering ? Theme.brandColor : .secondary)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
