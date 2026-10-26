import SwiftUI

/// Colored label chip ("Urgent", "Needs reply"…). Fades in.
struct LabelChip: View {
    let label: EmailLabel
    var corrected = false
    var compact = false
    var delay: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: label.symbol)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
            Text(label.title)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            if corrected {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 8))
                    .help("You corrected this label")
            }
        }
        .foregroundStyle(label.color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(Capsule().fill(label.color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(label.color.opacity(0.25), lineWidth: 0.5))
        .fadeIn(delay: delay)
    }
}

/// Small pill (deadline, job, draft ready…).
struct Pill: View {
    let text: String
    var symbol: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct GuardBadge: View {
    let verdict: GuardVerdict
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.shield.fill")
            Text(verdict == .malicious ? "Dangerous" : "Suspicious")
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(verdict == .malicious ? Color.red : Color.orange))
        .shadow(color: .red.opacity(pulse ? 0.5 : 0), radius: pulse ? 6 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .help("Agentry's guard flagged this email. No draft is written automatically.")
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let color = Theme.avatarColor(for: name)
        Text(Theme.initials(name))
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(LinearGradient(colors: [color.opacity(0.9), color], startPoint: .top, endPoint: .bottom))
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.15)))
    }
}

/// Keyboard key hint, e.g. ⌘K.
struct KeyCap: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// A number that counts up from zero when it appears.
struct CountUpText: View {
    let value: Int
    var font: Font = .system(size: 34, weight: .bold, design: .rounded)
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CountingNumber(value: shown)
            .font(font)
            .monospacedDigit()
            .onAppear { animate(to: value) }
            .onChange(of: value) { _, new in animate(to: new) }
    }

    private func animate(to target: Int) {
        if reduceMotion {
            shown = Double(target)
        } else {
            withAnimation(.easeOut(duration: Motion.countUpDuration)) { shown = Double(target) }
        }
    }
}

private struct CountingNumber: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
    }
}

struct StatCard: View {
    let title: String
    let value: Int
    let symbol: String
    let color: Color
    var caption: String = ""
    var action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.15))
                        Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
                    }
                    .frame(width: 30, height: 30)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0)
                }
                CountUpText(value: value)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if !caption.isEmpty {
                        Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(hovering ? 0.45 : 0), lineWidth: 1)
            )
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
    }
}

struct EmptyStateView: View {
    var pet: Pet = .cat
    var mood: PetMood = .idle
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            PetView(pet: pet, mood: mood)
                .frame(width: 150, height: 150)
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SubtleButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fadeIn()
    }
}

struct SectionHeader: View {
    let title: String
    var symbol: String?
    var count: Int?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(color)
            }
            Text(title)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            Spacer()
        }
        .font(.system(size: 13, weight: .semibold))
    }
}

/// Header used at the top of each screen.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String = "") {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension Date {
    /// "10:42", "Yesterday", "Mon", "12 Oct": compact like a mail client.
    var mailStyle: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: self, to: .now).day, days < 7 {
            return formatted(.dateTime.weekday(.abbreviated))
        }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Inline help under the OAuth client ID field.
struct ClientIDHint: View {
    let clientID: String
    let valid: Bool

    var body: some View {
        HStack(spacing: 6) {
            if clientID.isEmpty {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Paste the OAuth client ID from Google Cloud, not your email.")
            } else if clientID.contains("@") {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("That's an email address. Paste the OAuth client ID instead.")
            } else if !valid {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("A client ID ends in .apps.googleusercontent.com")
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Looks good.")
            }
            Spacer(minLength: 4)
            Link("Get a client ID", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}
