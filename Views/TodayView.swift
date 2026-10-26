import SwiftData
import SwiftUI

/// Daily briefing: urgent emails, drafts waiting, today's reminders, job updates.
struct TodayView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \Email.receivedAt, order: .reverse) private var emails: [Email]
    @Query(sort: \Draft.createdAt, order: .reverse) private var drafts: [Draft]
    @Query(sort: \Reminder.dueAt) private var reminders: [Reminder]
    @Query(sort: \JobApplication.lastUpdate, order: .reverse) private var jobs: [JobApplication]

    var body: some View {
        let b = app.briefing.make(emails: emails, drafts: drafts, reminders: reminders, jobs: jobs, name: app.settings.firstName)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(b)
                stats(b)
                if emails.isEmpty && app.polling.isChecking {
                    loading
                } else if b.isAllClear {
                    allClear
                } else {
                    columns(b)
                }
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ b: Briefing) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(b.greeting)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(b.headline)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill()
        }
        .fadeIn()
    }

    private func stats(_ b: Briefing) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
            StatCard(title: "Urgent", value: b.urgent.count, symbol: "flame.fill", color: .red,
                     caption: b.urgent.first?.sender ?? "Nothing on fire") {
                app.inboxFilter = .urgent
                withMotion { app.section = .inbox }
            }
            StatCard(title: "Drafts waiting", value: b.waitingDrafts.count, symbol: "checkmark.bubble.fill", color: Theme.brandColor,
                     caption: b.waitingDrafts.isEmpty ? "Review queue clear" : "Approve with ⌘↩") {
                withMotion { app.section = .review }
            }
            StatCard(title: "Reminders today", value: b.reminders.filter { $0.status != .done }.count, symbol: "bell.fill", color: .orange,
                     caption: b.reminders.first(where: { $0.status != .done }).map { $0.dueAt.formatted(date: .omitted, time: .shortened) + " · " + $0.text } ?? "Free day") {
                withMotion { app.section = .reminders }
            }
            StatCard(title: "Job updates", value: b.jobUpdates.count, symbol: "briefcase.fill", color: .brown,
                     caption: b.jobUpdates.first.map { "\($0.company) · \($0.stage.title)" } ?? "Last 3 days") {
                withMotion { app.section = .jobs }
            }
        }
    }

    private func columns(_ b: Briefing) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            if !b.waitingDrafts.isEmpty {
                BriefCard(title: "Drafts waiting for you", symbol: "checkmark.bubble.fill", color: Theme.brandColor, count: b.waitingDrafts.count) {
                    ForEach(b.waitingDrafts.prefix(5)) { draft in
                        BriefRow(name: draft.email?.sender ?? "", title: draft.email?.subject ?? "", detail: MailText.snippet(draft.body, length: 80),
                                 trailing: "Review") { app.openReview(draft) }
                    }
                }
            }
            if !b.urgent.isEmpty || !b.needsReply.isEmpty {
                BriefCard(title: "Needs your attention", symbol: "flame.fill", color: .red, count: b.urgent.count + b.needsReply.count) {
                    ForEach((b.urgent + b.needsReply).prefix(6)) { email in
                        BriefRow(name: email.sender, title: email.subject, detail: email.reason, label: email.effectiveLabel,
                                 trailing: email.deadline.map { "Due " + $0.formatted(.dateTime.day().month(.abbreviated)) } ?? email.receivedAt.mailStyle) {
                            app.selectedEmailID = email.gmailID
                            withMotion { app.section = .inbox }
                        }
                    }
                }
            }
            if !b.reminders.isEmpty {
                BriefCard(title: "Today's reminders", symbol: "bell.fill", color: .orange, count: b.reminders.filter { $0.status != .done }.count) {
                    ForEach(b.reminders) { r in
                        HStack(spacing: 10) {
                            ReminderCheckbox(isDone: r.status == .done) { app.completeReminder(r) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.text).strikethrough(r.status == .done).foregroundStyle(r.status == .done ? .secondary : .primary)
                                Text(r.dueAt.formatted(date: .omitted, time: .shortened) + (r.status == .late ? " · late" : ""))
                                    .font(.system(size: 11)).foregroundStyle(r.status == .late ? .red : .secondary)
                            }
                            .font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            if !b.jobUpdates.isEmpty {
                BriefCard(title: "Job updates", symbol: "briefcase.fill", color: .brown, count: b.jobUpdates.count) {
                    ForEach(b.jobUpdates.prefix(5)) { job in
                        HStack(spacing: 10) {
                            Avatar(name: job.company, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(job.company).font(.system(size: 13, weight: .semibold))
                                Text(job.role.isEmpty ? job.lastEmailSubject : job.role).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Pill(text: job.stage.title, symbol: job.stage.symbol, color: job.stage.color)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture { withMotion { app.section = .jobs } }
                    }
                }
            }
        }
    }

    private var allClear: some View {
        VStack(spacing: 10) {
            PetView(pet: .dog, mood: .idle)
                .frame(width: 180, height: 180)
            Text("You're all caught up")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("No urgent mail, no drafts waiting. Agentry keeps watch every \(app.settings.checkIntervalMinutes) minutes.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .card()
        .fadeIn(delay: 0.1)
    }

    private var loading: some View {
        VStack(spacing: 12) {
            PetView(pet: .cat, mood: .idle).frame(width: 140, height: 140)
            Text("Reading your inbox…").font(.system(size: 17, weight: .semibold, design: .rounded))
            if let p = app.polling.progress, p.total > 0 {
                ProgressView(value: Double(p.done), total: Double(p.total))
                    .frame(width: 240)
                Text("Triaged \(p.done) of \(p.total)").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .card()
    }
}

/// AI model + last check, shown on Today.
struct StatusPill: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(app.polling.lastError != nil ? Color.orange : (app.polling.isChecking ? Theme.brandColor : .green))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.polling.isChecking ? "Checking mail…" : app.polling.lastError != nil ? "Check failed" : "Watching your inbox")
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .help(app.polling.lastError ?? "")
    }

    private var subtitle: String {
        let model = app.ai.kind.shortTitle
        if let last = app.polling.lastCheck {
            return "\(model) · \(last.formatted(.relative(presentation: .named)))"
        }
        return model
    }
}

private struct BriefCard<Content: View>: View {
    let title: String
    let symbol: String
    let color: Color
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, symbol: symbol, count: count, color: color)
            Divider()
            VStack(alignment: .leading, spacing: 2) { content() }
        }
        .card()
        .fadeIn(delay: 0.08)
    }
}

private struct BriefRow: View {
    let name: String
    let title: String
    let detail: String
    var label: EmailLabel?
    let trailing: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: name, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if let label { LabelChip(label: label, compact: true) }
                    }
                    Text(title).font(.system(size: 12)).lineLimit(1)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering ? Theme.brandColor : .secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
