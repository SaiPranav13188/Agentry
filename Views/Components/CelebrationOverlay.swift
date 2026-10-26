import SwiftUI

/// Shows the current cat/dog celebration: big centered card for achievements,
/// a small card in the corner for everyday wins.
struct CelebrationOverlay: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = app.achievements.current
        ZStack {
            if let c = current, c.size == .big {
                BigCelebration(celebration: c) { app.achievements.dismissCurrent() }
                    .id(c.id)
                    .transition(Motion.popTransition(reduceMotion: reduceMotion))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let c = current, c.size == .small {
                SmallCelebration(celebration: c) { app.achievements.dismissCurrent() }
                    .id(c.id)
                    .padding(.trailing, 22)
                    .padding(.bottom, app.sendService.pending.isEmpty ? 22 : 96)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Motion.resolved(Motion.bouncy, reduceMotion: reduceMotion), value: current?.id)
    }
}

private struct BigCelebration: View {
    let celebration: Celebration
    let dismiss: () -> Void
    @State private var appeared = false
    @State private var video: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.35))
                .background(.ultraThinMaterial.opacity(0.6))
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: 14) {
                ZStack {
                    SunburstView(color: celebration.pet == .cat ? .orange : Theme.brandColor)
                        .frame(width: 260, height: 260)
                    if let video {
                        LoopingVideoView(url: video)
                            .frame(width: 230, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 3))
                            .shadow(radius: 12)
                    } else {
                        PetView(pet: celebration.pet, mood: .celebrate)
                            .frame(width: 190, height: 190)
                    }
                }
                .frame(height: 220)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)

                if celebration.isUnlock {
                    Text("ACHIEVEMENT UNLOCKED")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Theme.brand)
                }
                HStack(spacing: 8) {
                    Image(systemName: celebration.symbol)
                        .foregroundStyle(Theme.brand)
                    Text(celebration.title)
                }
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)

                Text(celebration.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: dismiss) {
                    Text(celebration.pet == .cat ? "Purr-fect!" : "Woof, thanks!")
                        .frame(minWidth: 140)
                }
                .buttonStyle(BrandButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(width: 440)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
            )
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12)))

            ConfettiView(pet: celebration.pet)
                .ignoresSafeArea()
        }
        .onAppear {
            video = AchievementCenter.randomVideo(for: celebration.pet)
            withAnimation(Motion.resolved(Motion.bouncy).delay(0.05)) { appeared = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(7))
            dismiss()
        }
        .onExitCommand(perform: dismiss)
    }
}

private struct SmallCelebration: View {
    let celebration: Celebration
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PetView(pet: celebration.pet, mood: .celebrate, partyHat: false)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(celebration.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(celebration.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 8)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.brandColor.opacity(0.3)))
        .onTapGesture(perform: dismiss)
        .task {
            try? await Task.sleep(for: .seconds(2.8))
            dismiss()
        }
    }
}

/// Slowly rotating rays behind the pet.
struct SunburstView: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let angle = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.25
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                let rays = 14
                for i in 0..<rays {
                    let a0 = angle + Double(i) * 2 * .pi / Double(rays)
                    let a1 = a0 + .pi / Double(rays)
                    var p = Path()
                    p.move(to: center)
                    p.addLine(to: CGPoint(x: center.x + cos(a0) * radius, y: center.y + sin(a0) * radius))
                    p.addLine(to: CGPoint(x: center.x + cos(a1) * radius, y: center.y + sin(a1) * radius))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(color.opacity(0.13)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.62, y: center.y - radius * 0.62, width: radius * 1.24, height: radius * 1.24)),
                         with: .radialGradient(Gradient(colors: [color.opacity(0.28), color.opacity(0)]), center: center, startRadius: 0, endRadius: radius * 0.62))
            }
            .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 40, endRadius: 130))
        }
    }
}
