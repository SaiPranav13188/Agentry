import AppKit
import SwiftData
import SwiftUI

enum InboxFilter: String, CaseIterable, Identifiable {
    case all, urgent, needsReply, fyi, ignore, flagged, jobs, done
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .urgent: "Urgent"
        case .needsReply: "Needs reply"
        case .fyi: "FYI"
        case .ignore: "Ignore"
        case .flagged: "Flagged"
        case .jobs: "Jobs"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.fill"
        case .urgent: EmailLabel.urgent.symbol
        case .needsReply: EmailLabel.needsReply.symbol
        case .fyi: EmailLabel.fyi.symbol
        case .ignore: EmailLabel.ignore.symbol
        case .flagged: "exclamationmark.shield.fill"
        case .jobs: "briefcase.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    func matches(_ e: Email) -> Bool {
        switch self {
        case .done: return e.isDone
        case .all: return !e.isDone
        case .urgent: return !e.isDone && e.effectiveLabel == .urgent
        case .needsReply: return !e.isDone && e.effectiveLabel == .needsReply
        case .fyi: return !e.isDone && e.effectiveLabel == .fyi
        case .ignore: return !e.isDone && e.effectiveLabel == .ignore
        case .flagged: return e.isFlagged
        case .jobs: return e.isJobEmail
        }
    }
}

/// Recent triaged emails with label chips and reasons.
struct InboxView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Email.receivedAt, order: .reverse) private var emails: [Email]
    @State private var search = ""
    @Namespace private var filterNS

    private var visible: [Email] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return emails.filter { e in
            app.inboxFilter.matches(e) &&
                (q.isEmpty || e.subject.lowercased().contains(q) || e.sender.lowercased().contains(q) || e.body.lowercased().contains(q))
        }
    }

    var body: some View {
        let list = visible
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                filters
                Divider()
                if list.isEmpty {
                    emptyState
                } else {
                    emailList(list)
                }
            }
            .frame(minWidth: 380, idealWidth: 440, maxWidth: 520)

            Divider()

            if let email = list.first(where: { $0.gmailID == app.selectedEmailID }) ?? emails.first(where: { $0.gmailID == app.selectedEmailID }) {
                EmailDetailView(email: email)
                    .id(email.gmailID)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "envelope.open").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text("Select an email").foregroundStyle(.secondary)
                    HStack(spacing: 4) { KeyCap("J"); KeyCap("K"); Text("to move").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if app.selectedEmailID == nil { app.selectedEmailID = list.first?.gmailID }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Inbox").font(.system(size: 20, weight: .bold, design: .rounded))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(InboxFilter.allCases) { f in
                    let count = emails.filter(f.matches).count
                    let active = app.inboxFilter == f
                    Button {
                        withMotion(Motion.quick) { app.inboxFilter = f }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: f.symbol).font(.system(size: 9))
                            Text(f.title)
                            if count > 0 && f != .done {
                                Text("\(count)").foregroundStyle(active ? .white.opacity(0.85) : .secondary)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(active ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if active {
                                Capsule().fill(Theme.brand).matchedGeometryEffect(id: "filter", in: filterNS)
                            } else {
                                Capsule().fill(Color.primary.opacity(0.05))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func emailList(_ list: [Email]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.gmailID) { index, email in
                        EmailRow(email: email, selected: email.gmailID == app.selectedEmailID, index: index)
                            .id(email.gmailID)
                            .onTapGesture { withMotion(Motion.quick) { app.selectedEmailID = email.gmailID } }
                            .contextMenu { EmailContextMenu(email: email) }
                            .transition(Motion.rowTransition(reduceMotion: reduceMotion))
                    }
                }
                .padding(8)
                .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: list.map(\.gmailID))
            }
            .onChange(of: app.selectedEmailID) { _, id in
                if let id { withMotion(Motion.quick) { proxy.scrollTo(id) } }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(characters: .init(charactersIn: "jkerJKER1234")) { press in
            handleKey(press.characters.lowercased(), list: list)
        }
    }

    private func handleKey(_ key: String, list: [Email]) -> KeyPress.Result {
        let index = list.firstIndex { $0.gmailID == app.selectedEmailID }
        switch key {
        case "j", "k":
            let next = key == "j" ? (index.map { $0 + 1 } ?? 0) : (index.map { $0 - 1 } ?? 0)
            if list.indices.contains(next) { app.selectedEmailID = list[next].gmailID }
        case "e":
            guard let i = index else { return .ignored }
            let email = list[i]
            let neighbour = list.indices.contains(i + 1) ? list[i + 1] : (i > 0 ? list[i - 1] : nil)
            app.toggleDone(email)
            app.selectedEmailID = neighbour?.gmailID
        case "r":
            guard let i = index else { return .ignored }
            Task { await app.draftReply(for: list[i]) }
        case "1", "2", "3", "4":
            guard let i = index, let n = Int(key) else { return .ignored }
            app.correctLabel(list[i], to: EmailLabel.allCases[n - 1])
        default:
            return .ignored
        }
        return .handled
    }

    @ViewBuilder
    private var emptyState: some View {
        switch app.inboxFilter {
        case .all where emails.isEmpty && app.polling.isChecking:
            EmptyStateView(pet: .cat, mood: .idle, title: "Fetching your mail…", message: "Agentry is reading and labeling your newest emails.")
        case .all where emails.isEmpty:
            EmptyStateView(pet: .cat, mood: .sleep, title: "No emails yet", message: "Agentry checks every \(app.settings.checkIntervalMinutes) minutes.",
                           actionTitle: "Check now", action: { app.polling.checkNow() })
        case .all, .urgent, .needsReply:
            EmptyStateView(pet: .dog, mood: .celebrate, title: "Inbox Zero", message: "Nothing here needs you. Go enjoy a chai ☕️")
        case .flagged:
            EmptyStateView(pet: .dog, mood: .idle, title: "No threats", message: "Agentry's guard hasn't flagged anything. Good boy.")
        default:
            EmptyStateView(pet: .cat, mood: .sleep, title: "Nothing here", message: "No emails match this filter.")
        }
    }
}

private struct EmailRow: View {
    let email: Email
    let selected: Bool
    let index: Int
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(email.isRead ? Color.clear : Theme.brandColor)
                .frame(width: 7, height: 7)
                .padding(.top, 13)
            Avatar(name: email.sender, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(email.sender)
                        .font(.system(size: 13, weight: email.isRead ? .medium : .bold))
                        .lineLimit(1)
                    if email.isFlagged { GuardBadge(verdict: email.guardVerdict) }
                    Spacer()
                    Text(email.receivedAt.mailStyle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(email.subject)
                    .font(.system(size: 12.5, weight: email.isRead ? .regular : .semibold))
                    .lineLimit(1)
                if !email.reason.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(Theme.brandColor.opacity(0.8))
                        Text(email.reason).lineLimit(1)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    if let label = email.effectiveLabel {
                        LabelChip(label: label, corrected: email.userLabel != nil, compact: true, delay: Double(min(index, 12)) * Motion.chipStagger)
                    } else {
                        Pill(text: "Triaging…", symbol: "hourglass", color: .secondary)
                    }
                    if email.pendingDraft != nil {
                        Pill(text: "Draft ready", symbol: "square.and.pencil", color: Theme.brandColor)
                    }
                    if email.isJobEmail { Pill(text: "Job", symbol: "briefcase.fill", color: .brown) }
                    if let deadline = email.deadline {
                        Pill(text: deadline.formatted(.dateTime.day().month(.abbreviated)), symbol: "calendar", color: .red)
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.brandColor.opacity(0.13) : Color.primary.opacity(hovering ? 0.04 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.brandColor.opacity(0.35) : .clear)
        )
        .opacity(email.isDone ? 0.6 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Right-click menu, including "Correct label" (used for the triage eval).
struct EmailContextMenu: View {
    @Environment(AppState.self) private var app
    let email: Email

    var body: some View {
        Menu("Correct label") {
            ForEach(Array(EmailLabel.allCases.enumerated()), id: \.element) { i, label in
                Button {
                    app.correctLabel(email, to: label)
                } label: {
                    if email.effectiveLabel == label {
                        Label("\(label.title)  (\(i + 1))", systemImage: "checkmark")
                    } else {
                        Text("\(label.title)  (\(i + 1))")
                    }
                }
            }
            if email.userLabel != nil {
                Divider()
                Button("Use Agentry's label") { app.correctLabel(email, to: nil) }
            }
        }
        Button(email.isDone ? "Move back to Inbox" : "Mark done (E)") { app.toggleDone(email) }
        Button(email.pendingDraft == nil ? "Draft a reply (R)" : "Open draft (R)") {
            Task { await app.draftReply(for: email) }
        }
        Divider()
        Button("Copy sender address") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(email.senderAddress, forType: .string)
        }
    }
}

struct EmailDetailView: View {
    @Environment(AppState.self) private var app
    let email: Email
    @State private var drafting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        drafting = true
                        await app.draftReply(for: email)
                        drafting = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if drafting { ProgressView().controlSize(.small) } else { Image(systemName: "square.and.pencil") }
                        Text(email.pendingDraft == nil ? "Draft reply" : "Open draft")
                        KeyCap("R")
                    }
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(drafting)

                Button {
                    app.toggleDone(email)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: email.isDone ? "tray.and.arrow.up" : "checkmark")
                        Text(email.isDone ? "Move to Inbox" : "Done")
                        KeyCap("E")
                    }
                }
                .buttonStyle(SubtleButtonStyle())

                Menu {
                    EmailContextMenu(email: email)
                } label: {
                    Label("Label", systemImage: "tag")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if email.isFlagged { guardBanner }
                    EmailContent(email: email)
                }
                .padding(20)
            }
        }
        .onAppear {
            if !email.isRead {
                email.isRead = true
                app.save()
            }
        }
    }

    private var guardBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 22))
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(email.guardVerdict == .malicious ? "This email looks dangerous" : "This email looks suspicious")
                    .font(.system(size: 14, weight: .bold))
                Text(email.guardReason)
                    .font(.system(size: 12.5))
                Text("Agentry didn't write a reply. Don't click its links or share codes or passwords.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.red.opacity(0.3)))
        .fadeIn()
    }
}
