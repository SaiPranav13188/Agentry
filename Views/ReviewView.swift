import SwiftData
import SwiftUI

/// Drafts waiting for approval: original email on the left, editable draft on the right.
struct ReviewView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Draft> { $0.statusRaw == "pending" || $0.statusRaw == "sending" },
           sort: \Draft.createdAt, order: .reverse)
    private var drafts: [Draft]

    var body: some View {
        HStack(spacing: 0) {
            queue
                .frame(width: 290)
            Divider()
            Group {
                if let draft = selected {
                    DraftDetailView(draft: draft)
                        .id(draft.uuid)
                        .transition(.opacity)
                } else {
                    EmptyStateView(
                        pet: .cat, mood: .idle,
                        title: "Review queue clear",
                        message: "When an email needs a reply, Agentry writes a draft here. Nothing is ever sent without your click.",
                        actionTitle: "Go to Inbox", action: { withMotion { app.section = .inbox } }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: drafts.map(\.uuid)) { ensureSelection() }
    }

    private var selected: Draft? {
        drafts.first { $0.uuid == app.selectedDraftUUID }
    }

    private func ensureSelection() {
        if selected == nil {
            app.selectedDraftUUID = drafts.first(where: { $0.status == .pending })?.uuid ?? drafts.first?.uuid
        }
    }

    private func move(_ offset: Int) {
        guard let i = drafts.firstIndex(where: { $0.uuid == app.selectedDraftUUID }) else { return }
        let j = min(max(i + offset, 0), drafts.count - 1)
        withMotion(Motion.quick) { app.selectedDraftUUID = drafts[j].uuid }
    }

    private var queue: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review").font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                if !drafts.isEmpty {
                    Text("\(drafts.count) waiting")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                Text("AI can only draft. Only you can send.")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(drafts) { draft in
                        DraftRow(draft: draft, selected: draft.uuid == app.selectedDraftUUID, sending: app.sendService.isSending(draft))
                            .onTapGesture { withMotion(Motion.quick) { app.selectedDraftUUID = draft.uuid } }
                            .transition(Motion.rowTransition(reduceMotion: reduceMotion))
                    }
                }
                .padding(8)
                .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: drafts.map(\.uuid))
            }
        }
        .background(Color.primary.opacity(0.02))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress("j") { move(1); return .handled }
        .onKeyPress("k") { move(-1); return .handled }
    }
}

private struct DraftRow: View {
    let draft: Draft
    let selected: Bool
    let sending: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: draft.email?.sender ?? "?", size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(draft.email?.sender ?? "Unknown").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(draft.createdAt.mailStyle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(draft.email?.subject ?? "").font(.system(size: 12)).lineLimit(1)
                HStack(spacing: 6) {
                    if sending {
                        Pill(text: "Sending…", symbol: "paperplane.fill", color: Theme.brandColor)
                    } else if let label = draft.email?.effectiveLabel {
                        LabelChip(label: label, compact: true)
                    }
                    if draft.wasEdited {
                        Pill(text: "Edited", symbol: "pencil", color: .secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.brandColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.04 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.brandColor.opacity(0.4) : .clear)
        )
        .opacity(sending ? 0.7 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Detail

struct DraftDetailView: View {
    @Environment(AppState.self) private var app
    let draft: Draft

    @State private var text: String = ""
    @State private var instruction = ""
    @State private var editTask: Task<Void, Never>?
    @State private var confirmReject = false
    @FocusState private var editorFocused: Bool

    private var isSending: Bool { app.sendService.isSending(draft) }
    private var isRevising: Bool { app.revisingDraftUUIDs.contains(draft.uuid) }
    private var isSyncing: Bool { app.syncingDraftUUIDs.contains(draft.uuid) }

    var body: some View {
        HSplitView {
            if let email = draft.email {
                OriginalEmailPane(email: email)
                    .frame(minWidth: 280, idealWidth: 380)
            }
            editorPane
                .frame(minWidth: 380, idealWidth: 520)
        }
        .onAppear { text = draft.body }
        .onChange(of: draft.body) { _, new in
            // AI revisions arrive here; don't clobber what you're typing.
            if editTask == nil { text = new }
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Your reply").font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    approvalBadge
                }
                if let email = draft.email {
                    HStack(spacing: 6) {
                        Text("To").foregroundStyle(.secondary)
                        Text(email.sender).fontWeight(.medium)
                        Text("<\(email.senderAddress)>").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                    HStack(spacing: 6) {
                        Text("Subject").foregroundStyle(.secondary)
                        Text(email.replyContext.replySubject)
                    }
                    .font(.system(size: 12))
                    .lineLimit(1)
                }
            }
            .padding(20)

            Divider()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .focused($editorFocused)
                    .disabled(isSending || isRevising)
                    .onChange(of: text) { _, new in scheduleEdit(new) }
                if isRevising {
                    RevisingShimmer()
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            VStack(spacing: 12) {
                askAI
                actions
            }
            .padding(16)
        }
        .background(Theme.cardBackground.opacity(0.4))
    }

    private var approvalBadge: some View {
        HStack(spacing: 5) {
            if isSyncing {
                ProgressView().controlSize(.mini)
                Text("Saving to Gmail…")
            } else {
                Image(systemName: "lock.fill").foregroundStyle(.green)
                Text("Approval \(draft.approvalID.prefix(4).lowercased()) · \(timeLeft)")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .help("Each version of a draft gets a one-time approval that expires in 24 hours. Editing creates a new one.")
    }

    private var timeLeft: String {
        let hours = Int(draft.expiresAt.timeIntervalSinceNow / 3600)
        return hours >= 1 ? "\(hours)h left" : "expires soon"
    }

    private var askAI: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.brand)
            TextField("Ask AI to change… (e.g. “shorter”, “more formal”, “say I'm free Thursday”)", text: $instruction)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(revise)
                .disabled(isRevising || isSending)
            if isRevising {
                ProgressView().controlSize(.small)
            } else if !instruction.isEmpty {
                Button("Rewrite", action: revise)
                    .buttonStyle(SubtleButtonStyle(tint: Theme.brandColor))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.brandColor.opacity(0.25)))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                confirmReject = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Reject")
                    KeyCap("⌘⌫")
                }
            }
            .buttonStyle(SubtleButtonStyle(tint: .red))
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(isSending)
            .confirmationDialog("Reject this draft?", isPresented: $confirmReject) {
                Button("Reject and delete draft", role: .destructive) { app.reject(draft) }
            } message: {
                Text("The Gmail draft will be deleted. The email stays in your inbox.")
            }

            Spacer()

            if draft.wasEdited {
                Button("Restore AI version") {
                    text = draft.originalBody
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .disabled(isSending)
            }

            Button {
                send()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSending ? "clock.fill" : "paperplane.fill")
                    Text(isSending ? "Sending…" : "Send")
                    Text("⌘↩").font(.system(size: 11, weight: .medium)).opacity(0.8)
                }
            }
            .buttonStyle(BrandButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isSending || isRevising || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Sends after a 30-second undo window.")
        }
    }

    private func scheduleEdit(_ new: String) {
        guard new != draft.body else { return }
        editTask?.cancel()
        editTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await app.applyEdit(draft, body: new)
            editTask = nil
        }
    }

    private func revise() {
        let ask = instruction
        guard !ask.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        editTask?.cancel()
        editTask = nil
        Task {
            if text != draft.body { await app.applyEdit(draft, body: text) }
            await app.revise(draft, instruction: ask)
            text = draft.body
            instruction = ""
        }
    }

    private func send() {
        editTask?.cancel()
        editTask = nil
        let shown = text
        Task { await app.send(draft, shownBody: shown) }
    }
}

/// Left pane: the email you're replying to.
struct OriginalEmailPane: View {
    let email: Email

    var body: some View {
        ScrollView {
            EmailContent(email: email)
                .padding(20)
        }
    }
}

/// Header, chips, Agentry's take and body of an email.
struct EmailContent: View {
    let email: Email

    var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Avatar(name: email.sender, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(email.sender).font(.system(size: 14, weight: .semibold))
                        Text(email.senderAddress).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(email.receivedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(email.subject)
                    .font(.system(size: 17, weight: .bold))
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    if let label = email.effectiveLabel { LabelChip(label: label, corrected: email.userLabel != nil) }
                    if let deadline = email.deadline {
                        Pill(text: "Due \(deadline.formatted(.dateTime.day().month(.abbreviated)))", symbol: "calendar", color: .red)
                    }
                    if email.isJobEmail { Pill(text: "Job", symbol: "briefcase.fill", color: .brown) }
                    if email.isFlagged { GuardBadge(verdict: email.guardVerdict) }
                }

                AgentryTake(email: email)

                Divider()

                Text(email.body)
                    .font(.system(size: 13.5))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
    }
}

/// "Why Agentry labeled this" callout.
struct AgentryTake: View {
    let email: Email

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.brand)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agentry's take").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                Text(email.reason.isEmpty ? "Not triaged yet." : email.reason).font(.system(size: 13))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.brandColor.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.brandColor.opacity(0.18)))
    }
}

/// Animated shimmer while the AI rewrites the draft.
private struct RevisingShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            GeometryReader { geo in
                LinearGradient(colors: [.clear, Theme.brandColor.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: (phase * 1.5 - 0.5) * geo.size.width)
            }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Rewriting…")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.brand))
            .padding(.top, 10)
        }
    }
}
