import SwiftUI

/// First run: welcome → choose Apple Mail, demo or Gmail → notifications → done.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var name = ""
    @State private var chosenMode: MailMode = .appleMail
    @State private var connecting = false

    var body: some View {
        ZStack {
            background
            VStack {
                Spacer()
                Group {
                    switch step {
                    case 0: welcome
                    case 1: chooseInbox
                    default: notifications
                    }
                }
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxWidth: 560)
                Spacer()
                dots.padding(.bottom, 26)
            }
            .padding(40)
        }
        .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: step)
        .onAppear { name = app.settings.userName }
    }

    private var background: some View {
        ZStack {
            Theme.windowBackground
            Circle().fill(Theme.brandColor.opacity(0.18)).frame(width: 520).blur(radius: 120).offset(x: -260, y: -200)
            Circle().fill(Color.orange.opacity(0.12)).frame(width: 420).blur(radius: 120).offset(x: 300, y: 220)
        }
        .ignoresSafeArea()
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i == step ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: i == step ? 22 : 7, height: 7)
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            HStack(spacing: -24) {
                PetView(pet: .cat, mood: .idle, partyHat: false).frame(width: 140, height: 140)
                PetView(pet: .dog, mood: .idle, partyHat: false).frame(width: 140, height: 140)
            }
            Text("Meet Agentry")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
            Text("Your private email assistant. It reads your mail, tells you what matters, and drafts replies in your style. It never sends anything without your click.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                feature("tag.fill", .indigo, "Triage", "Every email labeled urgent, needs reply, FYI or ignore, with a reason.")
                feature("square.and.pencil", .purple, "Drafts in your voice", "Replies written on your Mac by on-device AI. Free and private.")
                feature("lock.shield.fill", .green, "You approve every send", "Send, edit or reject. 30 seconds to undo.")
                feature("bell.badge.fill", .orange, "Reminders, briefing & jobs", "“Remind me Friday at 4”, a morning summary, and a job tracker that updates itself.")
            }
            .card(padding: 18)

            HStack {
                TextField("What should I call you?", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Button("Get started") {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty { app.settings.userName = name }
                    step = 1
                }
                .buttonStyle(BrandButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var chooseInbox: some View {
        @Bindable var settings = app.settings
        return VStack(spacing: 18) {
            Text("Pick an inbox")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
            Text("You can switch any time in Settings.")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                choice(
                    symbol: "envelope.fill", color: .blue, title: "Use Apple Mail",
                    text: "Your real Gmail, with no Google sign-in here. Agentry uses the accounts in the Mail app and sends only what you approve.",
                    button: connecting ? "Connecting…" : "Use Apple Mail", recommended: true
                ) {
                    Task {
                        connecting = true
                        let ok = await app.connectAppleMail()
                        connecting = false
                        if ok {
                            chosenMode = .appleMail
                            step = 2
                        }
                    }
                }
                choice(
                    symbol: "sparkles.rectangle.stack.fill", color: .orange, title: "Try the demo inbox",
                    text: "Ten realistic sample emails: a deadline, a phishing attempt, interview invites. Nothing real is sent.",
                    button: "Use demo"
                ) {
                    app.finishOnboarding(mode: .demo)
                    Task { await app.notifications.requestAuthorization() }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("Apple Mail needs Gmail added once in")
                Button("System Settings → Internet Accounts") { AppleMailService.openInternetAccounts() }
                    .buttonStyle(.link)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            DisclosureGroup("Advanced: sign in with a Google Cloud OAuth client") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("1234-abc.apps.googleusercontent.com", text: $settings.gmailClientID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .autocorrectionDisabled()
                        .textContentType(nil)
                    ClientIDHint(clientID: settings.gmailClientID, valid: settings.gmailClientIDLooksValid)
                    Button {
                        Task {
                            await app.signIn()
                            if app.gmail.isSignedIn {
                                chosenMode = .gmail
                                step = 2
                            }
                        }
                    } label: {
                        HStack {
                            if app.signingIn { ProgressView().controlSize(.small) }
                            Text("Sign in with Google")
                        }
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .disabled(!settings.gmailClientIDLooksValid || app.signingIn)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 12))
            .frame(width: 536)
        }
    }

    private func choice(symbol: String, color: Color, title: String, text: String, button: String,
                        recommended: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(color)
                Spacer()
                if recommended { Pill(text: "Recommended", symbol: "star.fill", color: Theme.brandColor) }
            }
            Text(title).font(.system(size: 16, weight: .bold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if recommended {
                Button(action: action) { Text(button).frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle())
                    .disabled(connecting)
            } else {
                Button(action: action) { Text(button).frame(maxWidth: .infinity) }
                    .buttonStyle(SubtleButtonStyle(tint: color))
            }
        }
        .padding(18)
        .frame(width: 260, height: 240)
        .card(padding: 0)
    }

    private var notifications: some View {
        VStack(spacing: 18) {
            PetView(pet: .dog, mood: .celebrate).frame(width: 170, height: 170)
            Text("You're connected!")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
            Text("Allow notifications so you can Send, Edit or Reject drafts right from the banner, and get reminders on time.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Allow notifications & start") {
                Task {
                    await app.notifications.requestAuthorization()
                    app.finishOnboarding(mode: chosenMode)
                }
            }
            .buttonStyle(BrandButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }
}
