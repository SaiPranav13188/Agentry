import SwiftUI

// MARK: - Toast

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .foregroundStyle(toast.isError ? .orange : .green)
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.15), radius: 12, y: 4))
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .frame(maxWidth: 520)
    }
}

// MARK: - Undo bar

/// Bottom bar shown while a send waits out its 30-second window. The bar shrinks as time runs out.
struct UndoBarStack: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(app.sendService.pending) { item in
                UndoBar(item: item, window: app.sendService.undoWindow) {
                    app.sendService.undo(approvalID: item.id)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 18)
        .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: app.sendService.pending.map(\.id))
    }
}

private struct UndoBar: View {
    let item: SendService.PendingSend
    let window: TimeInterval
    let undo: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0)) { timeline in
            let remaining = max(0, item.deadline.timeIntervalSince(timeline.date))
            let fraction = window > 0 ? remaining / window : 0
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(Theme.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(remaining.rounded(.up)))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sending \(item.summary.lowercased())…")
                            .font(.system(size: 13, weight: .semibold))
                        Text("You can still change your mind.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 20)
                    Button(action: undo) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Undo")
                            KeyCap("⌘Z")
                        }
                    }
                    .buttonStyle(SubtleButtonStyle(tint: Theme.brandColor))
                    .keyboardShortcut("z", modifiers: .command)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.brand)
                        .frame(width: geo.size.width * fraction, height: 3)
                }
                .frame(height: 3)
            }
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial).shadow(color: .black.opacity(0.2), radius: 18, y: 6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        }
    }
}

// MARK: - Command palette (⌘K)

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var shortcut: String = ""
    let run: () -> Void
}

struct CommandPalette: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var commands: [PaletteCommand] {
        var list: [PaletteCommand] = AppSection.allCases.map { s in
            PaletteCommand(title: "Go to \(s.title)", symbol: s.symbol, shortcut: "⌘\(s.shortcut)") { withMotion { app.section = s } }
        }
        list += [
            PaletteCommand(title: "Check for new mail", symbol: "arrow.clockwise", shortcut: "⌘R") { app.polling.checkNow() },
            PaletteCommand(title: "Add a reminder…", symbol: "bell.badge", shortcut: "") { withMotion { app.section = .reminders } },
            PaletteCommand(title: "Show urgent emails", symbol: "flame.fill") {
                app.inboxFilter = .urgent
                withMotion { app.section = .inbox }
            },
            PaletteCommand(title: "Show flagged emails", symbol: "exclamationmark.shield") {
                app.inboxFilter = .flagged
                withMotion { app.section = .inbox }
            },
            PaletteCommand(title: "Celebrate with a cat 🐱", symbol: "cat.fill") { app.achievements.preview(.cat) },
            PaletteCommand(title: "Celebrate with a dog 🐶", symbol: "dog.fill") { app.achievements.preview(.dog) },
            PaletteCommand(title: "Keyboard shortcuts", symbol: "keyboard", shortcut: "?") { app.showShortcuts = true },
        ]
        if app.settings.mailMode == .demo {
            list.append(PaletteCommand(title: "Connect Gmail…", symbol: "envelope.badge.person.crop") { withMotion { app.section = .settings } })
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { cmd in
            let title = cmd.title.lowercased()
            if title.contains(q) { return true }
            // Fuzzy: all query letters in order.
            var it = title.makeIterator()
            return q.allSatisfy { ch in
                while let next = it.next() { if next == ch { return true } }
                return false
            }
        }
    }

    var body: some View {
        let items = commands
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.brand)
                    TextField("Type a command…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .focused($focused)
                        .onSubmit { run(items) }
                    KeyCap("esc")
                }
                .padding(16)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, cmd in
                                HStack(spacing: 12) {
                                    Image(systemName: cmd.symbol)
                                        .frame(width: 20)
                                        .foregroundStyle(index == highlighted ? .white : .secondary)
                                    Text(cmd.title)
                                        .foregroundStyle(index == highlighted ? .white : .primary)
                                    Spacer()
                                    if !cmd.shortcut.isEmpty {
                                        Text(cmd.shortcut)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(index == highlighted ? .white.opacity(0.85) : .secondary)
                                    }
                                }
                                .font(.system(size: 14))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(index == highlighted ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.clear))
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    highlighted = index
                                    run(items)
                                }
                                .onHover { if $0 { highlighted = index } }
                                .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: highlighted) { _, new in proxy.scrollTo(new) }
                }
                if items.isEmpty {
                    Text("No matching command").foregroundStyle(.secondary).padding(20)
                }
            }
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial).shadow(color: .black.opacity(0.3), radius: 30, y: 12))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(0, items.count - 1))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onExitCommand { close() }
    }

    private func run(_ items: [PaletteCommand]) {
        guard items.indices.contains(highlighted) else { return }
        let cmd = items[highlighted]
        close()
        cmd.run()
    }

    private func close() {
        withMotion(Motion.quick) { app.showCommandPalette = false }
    }
}

// MARK: - Shortcuts sheet

struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let groups: [(String, [(String, String)])] = [
        ("Everywhere", [("⌘K", "Command palette"), ("⌘1 – ⌘7", "Switch screens"), ("⌘R", "Check for new mail"), ("⌘Z", "Undo send"), ("?", "This list")]),
        ("Inbox", [("J / K", "Next / previous email"), ("E", "Mark done"), ("R", "Draft or open reply"), ("1 – 4", "Correct label")]),
        ("Review", [("⌘↩", "Send (after 30 s undo)"), ("⌘⌫", "Reject draft"), ("J / K", "Next / previous draft")]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Keyboard shortcuts").font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ForEach(groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.0.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    ForEach(group.1, id: \.0) { row in
                        HStack {
                            Text(row.1)
                            Spacer()
                            KeyCap(row.0)
                        }
                        .font(.system(size: 13))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
