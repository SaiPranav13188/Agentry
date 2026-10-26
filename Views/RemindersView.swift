import SwiftData
import SwiftUI

struct RemindersView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Reminder.dueAt) private var reminders: [Reminder]

    @State private var input = ""
    @State private var parsing = false
    @State private var parsed: ParsedReminder?
    @State private var parseFailed = false
    @State private var showDone = false
    @FocusState private var inputFocused: Bool

    private let examples = ["tomorrow 9am pay rent", "in 30 minutes stretch", "Friday at 4 call Ravi", "every weekday at 10 standup"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "Reminders", subtitle: "Just type it. Times are in India Standard Time.")
                composer
                if let parsed {
                    ConfirmCard(parsed: Binding(get: { parsed }, set: { self.parsed = $0 }), save: save, cancel: { withMotion { self.parsed = nil } })
                        .transition(Motion.popTransition(reduceMotion: reduceMotion))
                }
                lists
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: parsed)
        }
        .onAppear { inputFocused = true }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 16))
                TextField("Remind me Friday at 4 to call Ravi…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($inputFocused)
                    .onSubmit(parse)
                if parsing {
                    ProgressView().controlSize(.small)
                } else if !input.isEmpty {
                    Button(action: parse) {
                        HStack(spacing: 4) { Text("Set"); KeyCap("↩") }
                    }
                    .buttonStyle(SubtleButtonStyle(tint: .orange))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(inputFocused ? Color.orange.opacity(0.5) : Theme.hairline))

            if parseFailed {
                Label("I couldn't find a time in that. Try “tomorrow at 6pm …”.", systemImage: "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 6) {
                    Text("Try:").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(examples, id: \.self) { ex in
                        Button(ex) {
                            input = ex
                            parse()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var lists: some View {
        let open = reminders.filter { $0.status != .done }
        let due = open.filter { $0.status == .fired || $0.status == .late }
        let upcoming = open.filter { $0.status == .pending }
        let cal = Calendar.current
        let today = upcoming.filter { cal.isDateInToday($0.dueAt) }
        let tomorrow = upcoming.filter { cal.isDateInTomorrow($0.dueAt) }
        let later = upcoming.filter { !cal.isDateInToday($0.dueAt) && !cal.isDateInTomorrow($0.dueAt) }
        let done = reminders.filter { $0.status == .done }.sorted { $0.dueAt > $1.dueAt }

        if open.isEmpty && parsed == nil {
            EmptyStateView(pet: .cat, mood: .sleep, title: "Nothing to remember",
                           message: "Add one above. Agentry will nudge you with a notification, even if you snooze it.")
                .frame(height: 300)
        }
        group("Due now", symbol: "alarm.fill", color: .red, items: due)
        group("Today", symbol: "sun.max.fill", color: .orange, items: today)
        group("Tomorrow", symbol: "sunrise.fill", color: .yellow, items: tomorrow)
        group("Later", symbol: "calendar", color: .blue, items: later)

        if !done.isEmpty {
            DisclosureGroup(isExpanded: $showDone) {
                VStack(spacing: 2) {
                    ForEach(done.prefix(15)) { ReminderRow(reminder: $0) }
                }
                .padding(.top, 6)
            } label: {
                SectionHeader(title: "Done", symbol: "checkmark.circle.fill", count: done.count, color: .green)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, symbol: String, color: Color, items: [Reminder]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: title, symbol: symbol, count: items.count, color: color)
                VStack(spacing: 2) {
                    ForEach(items) { r in
                        ReminderRow(reminder: r)
                            .transition(Motion.rowTransition(reduceMotion: reduceMotion))
                    }
                }
                .card(padding: 6)
            }
            .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: items.map(\.uuid))
        }
    }

    private func parse() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        parsing = true
        parseFailed = false
        Task {
            let result = await app.reminders.parse(text)
            parsing = false
            if let result {
                withMotion(Motion.bouncy) { parsed = result }
            } else {
                parseFailed = true
            }
        }
    }

    private func save() {
        guard let parsed else { return }
        app.saveReminder(parsed)
        withMotion {
            self.parsed = nil
            input = ""
        }
        inputFocused = true
    }
}

/// "Here's what I understood" card shown before saving.
private struct ConfirmCard: View {
    @Binding var parsed: ParsedReminder
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                Text("Here's what I understood").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            }
            TextField("What", text: $parsed.text)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
            HStack(spacing: 14) {
                DatePicker("", selection: $parsed.dueAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.timeZone, ReminderService.timeZone)
                Picker("", selection: $parsed.recurrence) {
                    ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Text(parsed.dueAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(SubtleButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.fill")
                        Text("Save reminder")
                    }
                }
                .buttonStyle(BrandButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .card(padding: 18)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.brandColor.opacity(0.35)))
    }
}

struct ReminderRow: View {
    @Environment(AppState.self) private var app
    let reminder: Reminder
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ReminderCheckbox(isDone: reminder.status == .done) {
                if reminder.status != .done { app.completeReminder(reminder) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.text)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(reminder.status == .done)
                    .foregroundStyle(reminder.status == .done ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(reminder.dueAt.formatted(date: .abbreviated, time: .shortened))
                    if reminder.isRecurring {
                        Label(reminder.recurrence.title, systemImage: "repeat").labelStyle(.titleAndIcon)
                    }
                    if reminder.status == .late {
                        Pill(text: "Late", symbol: "exclamationmark.circle.fill", color: .red)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if hovering && reminder.status != .done {
                Button {
                    app.snoozeReminder(reminder)
                } label: {
                    Label("1h", systemImage: "moon.zzz.fill")
                }
                .buttonStyle(SubtleButtonStyle())
                .help("Snooze 1 hour")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.04 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withMotion(Motion.quick) { hovering = h } }
        .contextMenu {
            if reminder.status != .done {
                Button("Mark done") { app.completeReminder(reminder) }
                Button("Snooze 1 hour") { app.snoozeReminder(reminder) }
            }
            Divider()
            Button("Delete", role: .destructive) {
                withMotion {
                    app.context.delete(reminder)
                    app.save()
                }
            }
        }
    }
}

/// Round checkbox with a springy check.
struct ReminderCheckbox: View {
    let isDone: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? Color.green : Color.secondary.opacity(0.5), lineWidth: 1.6)
                    .background(Circle().fill(isDone ? Color.green : .clear))
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 20, height: 20)
            .scaleEffect(pressed ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .motion(Motion.bouncy, value: isDone)
        .onLongPressGesture(minimumDuration: 0, pressing: { p in withMotion(Motion.quick) { pressed = p } }, perform: {})
    }
}
