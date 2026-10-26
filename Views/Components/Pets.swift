import AVKit
import SwiftUI

enum PetMood {
    case idle, celebrate, sleep
}

/// A hand-drawn, animated cat or dog (vector, no assets). Hops, wags, blinks and waves.
struct PetView: View {
    let pet: Pet
    var mood: PetMood = .celebrate
    var partyHat: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.35 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let s = min(size.width, size.height) / 200
                ctx.translateBy(x: (size.width - 200 * s) / 2, y: (size.height - 200 * s) / 2)
                ctx.scaleBy(x: s, y: s)
                let hat = partyHat ?? (mood == .celebrate)
                switch pet {
                case .cat: CatPainter.draw(&ctx, t: t, mood: mood, hat: hat)
                case .dog: DogPainter.draw(&ctx, t: t, mood: mood, hat: hat)
                }
            }
        }
        .accessibilityLabel(pet == .cat ? "Animated cat" : "Animated dog")
    }
}

// MARK: - Drawing helpers

private extension GraphicsContext {
    mutating func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)), with: .color(color))
    }

    mutating func poly(_ points: [CGPoint], _ color: Color) {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        fill(p, with: .color(color))
    }

    mutating func line(_ points: [CGPoint], _ color: Color, width: CGFloat) {
        var p = Path()
        p.addLines(points)
        stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// Run `body` rotated by `angle` radians around `pivot`.
    mutating func rotated(_ angle: Double, around pivot: CGPoint, _ body: (inout GraphicsContext) -> Void) {
        var copy = self
        copy.translateBy(x: pivot.x, y: pivot.y)
        copy.rotate(by: .radians(angle))
        copy.translateBy(x: -pivot.x, y: -pivot.y)
        body(&copy)
    }

    /// Happy closed eye "^".
    mutating func happyEye(_ cx: CGFloat, _ cy: CGFloat, _ color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: cx - 8, y: cy + 3))
        p.addQuadCurve(to: CGPoint(x: cx + 8, y: cy + 3), control: CGPoint(x: cx, y: cy - 9))
        stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
    }

    mutating func sleepyEye(_ cx: CGFloat, _ cy: CGFloat, _ color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: cx - 8, y: cy))
        p.addQuadCurve(to: CGPoint(x: cx + 8, y: cy), control: CGPoint(x: cx, y: cy + 7))
        stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    mutating func openEye(_ cx: CGFloat, _ cy: CGFloat, blink: CGFloat) {
        oval(cx, cy, 13, 15 * blink, Color(white: 0.12))
        if blink > 0.5 {
            oval(cx + 2.5, cy - 3, 4.5, 4.5, .white)
            oval(cx - 2.5, cy + 3, 2, 2, .white.opacity(0.8))
        }
    }

    mutating func partyHat(at center: CGPoint, tilt: Double) {
        rotated(tilt, around: center) { c in
            let base = center.y
            c.poly([CGPoint(x: center.x - 16, y: base), CGPoint(x: center.x + 16, y: base), CGPoint(x: center.x + 2, y: base - 38)],
                   Color(red: 0.49, green: 0.33, blue: 0.98))
            c.line([CGPoint(x: center.x - 10, y: base - 10), CGPoint(x: center.x + 11, y: base - 13)], Color.yellow, width: 3)
            c.line([CGPoint(x: center.x - 5, y: base - 22), CGPoint(x: center.x + 7, y: base - 24)], Color.pink, width: 3)
            c.oval(center.x + 2, base - 40, 10, 10, Color.yellow)
        }
    }

    mutating func zzz(t: Double, at origin: CGPoint) {
        for i in 0..<3 {
            let phase = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let p = CGPoint(x: origin.x + phase * 26, y: origin.y - phase * 40)
            var copy = self
            copy.opacity = 1 - phase
            copy.draw(Text("z").font(.system(size: 12 + phase * 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary), at: p)
        }
    }
}

private func blinkAmount(_ t: Double, period: Double = 3.7) -> CGFloat {
    t.truncatingRemainder(dividingBy: period) < 0.13 ? 0.12 : 1
}

// MARK: - Cat

private enum CatPainter {
    static let fur = Color(red: 0.98, green: 0.66, blue: 0.33)
    static let furDark = Color(red: 0.88, green: 0.50, blue: 0.20)
    static let cream = Color(red: 1.0, green: 0.94, blue: 0.84)
    static let pink = Color(red: 1.0, green: 0.62, blue: 0.68)
    static let ink = Color(white: 0.15)

    static func draw(_ ctx: inout GraphicsContext, t: Double, mood: PetMood, hat: Bool) {
        let celebrate = mood == .celebrate
        let hop: CGFloat = celebrate ? CGFloat(abs(sin(t * 4.2))) * 12 : (mood == .idle ? CGFloat(sin(t * 1.8)) * 1.5 : 0)

        // Shadow
        ctx.oval(100, 190, 100 - hop * 2, 10, .black.opacity(0.12 - Double(hop) * 0.004))

        var c = ctx
        c.translateBy(x: 0, y: -hop)

        // Tail
        let tailSwing = sin(t * (celebrate ? 5 : 2)) * (mood == .sleep ? 0.05 : 0.35)
        c.rotated(tailSwing, around: CGPoint(x: 138, y: 164)) { c in
            var tail = Path()
            tail.move(to: CGPoint(x: 138, y: 164))
            tail.addCurve(to: CGPoint(x: 172, y: 96), control1: CGPoint(x: 190, y: 160), control2: CGPoint(x: 160, y: 118))
            c.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 15, lineCap: .round))
            c.oval(172, 96, 15, 15, furDark)
        }

        // Body
        c.oval(100, 152, 98, 72, fur)
        c.oval(100, 162, 56, 44, cream)
        c.line([CGPoint(x: 62, y: 140), CGPoint(x: 70, y: 146)], furDark, width: 4)
        c.line([CGPoint(x: 138, y: 140), CGPoint(x: 130, y: 146)], furDark, width: 4)

        // Feet
        c.oval(74, 184, 28, 14, fur)
        c.oval(126, 184, 28, 14, fur)
        c.oval(84, 180, 20, 14, cream)

        // Waving paw
        if celebrate {
            let wave = -2.3 + sin(t * 9) * 0.45
            c.rotated(wave, around: CGPoint(x: 122, y: 146)) { c in
                var arm = Path(roundedRect: CGRect(x: 122, y: 139, width: 38, height: 15), cornerRadius: 7.5)
                arm = arm.applying(.identity)
                c.fill(arm, with: .color(fur))
                c.oval(160, 146.5, 18, 18, cream)
            }
        } else {
            c.oval(116, 180, 20, 14, cream)
        }

        // Head
        let headTilt = celebrate ? sin(t * 4.2) * 0.06 : (mood == .sleep ? 0.08 : sin(t * 0.9) * 0.03)
        c.rotated(headTilt, around: CGPoint(x: 100, y: 110)) { c in
            let twitch = t.truncatingRemainder(dividingBy: 4.3) < 0.18 ? 0.18 : 0
            // Ears
            c.rotated(-twitch, around: CGPoint(x: 72, y: 62)) { c in
                c.poly([CGPoint(x: 58, y: 78), CGPoint(x: 64, y: 30), CGPoint(x: 98, y: 58)], fur)
                c.poly([CGPoint(x: 66, y: 70), CGPoint(x: 69, y: 42), CGPoint(x: 88, y: 60)], pink)
            }
            c.poly([CGPoint(x: 142, y: 78), CGPoint(x: 136, y: 30), CGPoint(x: 102, y: 58)], fur)
            c.poly([CGPoint(x: 134, y: 70), CGPoint(x: 131, y: 42), CGPoint(x: 112, y: 60)], pink)

            c.oval(100, 94, 96, 88, fur)
            c.oval(100, 112, 58, 40, cream)
            // Forehead stripes
            c.line([CGPoint(x: 100, y: 52), CGPoint(x: 100, y: 64)], furDark, width: 4)
            c.line([CGPoint(x: 88, y: 54), CGPoint(x: 91, y: 64)], furDark, width: 3.5)
            c.line([CGPoint(x: 112, y: 54), CGPoint(x: 109, y: 64)], furDark, width: 3.5)

            // Eyes
            switch mood {
            case .celebrate:
                c.happyEye(80, 92, ink)
                c.happyEye(120, 92, ink)
            case .idle:
                let b = blinkAmount(t)
                c.openEye(80, 92, blink: b)
                c.openEye(120, 92, blink: b)
            case .sleep:
                c.sleepyEye(80, 94, ink)
                c.sleepyEye(120, 94, ink)
            }

            // Cheeks
            c.oval(68, 108, 16, 9, pink.opacity(0.65))
            c.oval(132, 108, 16, 9, pink.opacity(0.65))

            // Nose + mouth
            c.poly([CGPoint(x: 94, y: 103), CGPoint(x: 106, y: 103), CGPoint(x: 100, y: 110)], pink)
            if celebrate {
                var mouth = Path()
                mouth.move(to: CGPoint(x: 92, y: 113))
                mouth.addQuadCurve(to: CGPoint(x: 108, y: 113), control: CGPoint(x: 100, y: 128))
                mouth.closeSubpath()
                c.fill(mouth, with: .color(Color(red: 0.75, green: 0.25, blue: 0.3)))
                c.oval(100, 120, 8, 5, pink)
            } else {
                var mouth = Path()
                mouth.move(to: CGPoint(x: 91, y: 113))
                mouth.addQuadCurve(to: CGPoint(x: 100, y: 112), control: CGPoint(x: 95, y: 119))
                mouth.addQuadCurve(to: CGPoint(x: 109, y: 113), control: CGPoint(x: 105, y: 119))
                c.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }

            // Whiskers
            for (y1, y2) in [(106.0, 100.0), (111.0, 112.0)] {
                c.line([CGPoint(x: 76, y: y1), CGPoint(x: 44, y: y2)], ink.opacity(0.5), width: 1.4)
                c.line([CGPoint(x: 124, y: y1), CGPoint(x: 156, y: y2)], ink.opacity(0.5), width: 1.4)
            }

            if hat { c.partyHat(at: CGPoint(x: 112, y: 54), tilt: 0.3 + sin(t * 4.2) * 0.08) }
        }
        if mood == .sleep { c.zzz(t: t, at: CGPoint(x: 140, y: 50)) }
    }
}

// MARK: - Dog

private enum DogPainter {
    static let fur = Color(red: 0.86, green: 0.60, blue: 0.36)
    static let light = Color(red: 1.0, green: 0.93, blue: 0.82)
    static let ear = Color(red: 0.55, green: 0.34, blue: 0.20)
    static let ink = Color(white: 0.13)
    static let tongue = Color(red: 0.98, green: 0.45, blue: 0.52)

    static func draw(_ ctx: inout GraphicsContext, t: Double, mood: PetMood, hat: Bool) {
        let celebrate = mood == .celebrate
        let hop: CGFloat = celebrate ? CGFloat(abs(sin(t * 3.8))) * 14 : (mood == .idle ? CGFloat(sin(t * 1.6)) * 1.5 : 0)

        ctx.oval(100, 190, 104 - hop * 2, 10, .black.opacity(0.12 - Double(hop) * 0.004))

        var c = ctx
        c.translateBy(x: 0, y: -hop)

        // Wagging tail
        let wag = sin(t * (celebrate ? 16 : 5)) * (mood == .sleep ? 0.03 : 0.5)
        c.rotated(wag, around: CGPoint(x: 140, y: 150)) { c in
            var tail = Path()
            tail.move(to: CGPoint(x: 140, y: 150))
            tail.addCurve(to: CGPoint(x: 160, y: 104), control1: CGPoint(x: 176, y: 148), control2: CGPoint(x: 178, y: 112))
            c.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            c.oval(160, 104, 13, 13, light)
        }

        // Body
        c.oval(100, 154, 102, 68, fur)
        c.oval(100, 164, 58, 42, light)

        // Feet
        c.oval(72, 184, 30, 14, light)
        c.oval(128, 184, 30, 14, light)

        // Collar + tag
        var collar = Path()
        collar.move(to: CGPoint(x: 66, y: 128))
        collar.addQuadCurve(to: CGPoint(x: 134, y: 128), control: CGPoint(x: 100, y: 146))
        c.stroke(collar, with: .color(Color(red: 0.86, green: 0.2, blue: 0.25)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        let tagSwing = sin(t * (celebrate ? 8 : 2)) * 0.3
        c.rotated(tagSwing, around: CGPoint(x: 100, y: 138)) { c in
            c.oval(100, 146, 12, 12, Color(red: 1, green: 0.8, blue: 0.2))
        }

        // Head
        let headTilt = celebrate ? sin(t * 3.8) * 0.07 : (mood == .sleep ? -0.08 : sin(t * 0.8) * 0.03)
        c.rotated(headTilt, around: CGPoint(x: 100, y: 110)) { c in
            c.oval(100, 92, 94, 86, fur)

            // Floppy ears
            let flap = celebrate ? sin(t * 9) * 0.22 : sin(t * 1.5) * 0.04
            c.rotated(0.35 + flap, around: CGPoint(x: 64, y: 62)) { c in
                c.oval(56, 90, 28, 58, ear)
            }
            c.rotated(-0.35 - flap, around: CGPoint(x: 136, y: 62)) { c in
                c.oval(144, 90, 28, 58, ear)
            }

            // Brow spots
            c.oval(80, 76, 12, 7, light.opacity(0.9))
            c.oval(120, 76, 12, 7, light.opacity(0.9))

            // Snout
            c.oval(100, 114, 54, 38, light)

            // Eyes
            switch mood {
            case .celebrate:
                c.happyEye(80, 90, ink)
                c.happyEye(120, 90, ink)
            case .idle:
                let b = blinkAmount(t, period: 4.1)
                c.openEye(80, 90, blink: b)
                c.openEye(120, 90, blink: b)
            case .sleep:
                c.sleepyEye(80, 92, ink)
                c.sleepyEye(120, 92, ink)
            }

            // Nose
            c.oval(100, 104, 18, 12, ink)
            c.oval(96, 101, 5, 3, .white.opacity(0.6))

            // Mouth
            var mouth = Path()
            mouth.move(to: CGPoint(x: 100, y: 110))
            mouth.addLine(to: CGPoint(x: 100, y: 117))
            mouth.move(to: CGPoint(x: 88, y: 117))
            mouth.addQuadCurve(to: CGPoint(x: 100, y: 117), control: CGPoint(x: 94, y: 124))
            mouth.addQuadCurve(to: CGPoint(x: 112, y: 117), control: CGPoint(x: 106, y: 124))
            c.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            // Tongue
            if mood != .sleep {
                let sway = celebrate ? CGFloat(sin(t * 7)) * 2.5 : 0
                let length: CGFloat = celebrate ? 20 : 12
                let tongueRect = CGRect(x: 93 + sway, y: 119, width: 14, height: length)
                c.fill(Path(roundedRect: tongueRect, cornerRadius: 7), with: .color(tongue))
                c.line([CGPoint(x: 100 + sway, y: 121), CGPoint(x: 100 + sway, y: 119 + length - 6)], Color(red: 0.85, green: 0.3, blue: 0.38), width: 1.5)
            }

            c.oval(70, 108, 13, 7, tongue.opacity(0.35))
            c.oval(130, 108, 13, 7, tongue.opacity(0.35))

            if hat { c.partyHat(at: CGPoint(x: 88, y: 52), tilt: -0.3 + sin(t * 3.8) * 0.08) }
        }
        if mood == .sleep { c.zzz(t: t, at: CGPoint(x: 140, y: 50)) }
    }
}

// MARK: - Confetti

struct ConfettiView: View {
    var pet: Pet = .dog
    var count = 110
    var duration: Double = 3.6

    private struct Particle {
        var fromLeft: Bool
        var vx: Double
        var vy: Double
        var spin: Double
        var size: Double
        var color: Color
        var emoji: String?
        var shape: Int
    }

    @State private var start = Date()
    @State private var particles: [Particle] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                let g = 980.0
                for p in particles {
                    let x0 = p.fromLeft ? 0.0 : size.width
                    let x = x0 + p.vx * t * (p.fromLeft ? 1 : -1)
                    let y = size.height + p.vy * t + 0.5 * g * t * t
                    guard y < size.height + 40 else { continue }
                    var c = ctx
                    c.opacity = max(0, min(1, (duration - t) / 0.8))
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * t))
                    if let emoji = p.emoji {
                        c.draw(Text(emoji).font(.system(size: p.size * 2.2)), at: .zero)
                    } else if p.shape == 0 {
                        c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)), with: .color(p.color))
                    } else {
                        c.fill(Path(ellipseIn: CGRect(x: -p.size / 3, y: -p.size / 3, width: p.size / 1.5, height: p.size / 1.5)), with: .color(p.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .opacity(reduceMotion ? 0 : 1)
        .onAppear {
            start = .now
            let colors: [Color] = [.pink, .yellow, .mint, .orange, .purple, .blue, .red, .green, Theme.brandColor]
            let emojis = pet == .cat ? ["🐟", "🐾", "🧶", "⭐️"] : ["🦴", "🐾", "🎾", "⭐️"]
            particles = (0..<count).map { i in
                Particle(
                    fromLeft: i.isMultiple(of: 2),
                    vx: .random(in: 120...620),
                    vy: -.random(in: 650...1150),
                    spin: .random(in: -9...9),
                    size: .random(in: 7...13),
                    color: colors.randomElement()!,
                    emoji: Int.random(in: 0..<100) < 14 ? emojis.randomElement() : nil,
                    shape: Int.random(in: 0...1)
                )
            }
        }
    }
}

// MARK: - Your own videos

/// Plays a muted, looping video (your own cat/dog clips).
struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
    }
}
