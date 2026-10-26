import AppKit
import SwiftUI

/// Animation tokens. Every animation in Agentry goes through these so that
/// Reduce Motion is respected in one place.
enum Motion {
    /// Hover, press, small toggles.
    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.86)
    /// Default for list changes and panels.
    static let standard = Animation.spring(response: 0.38, dampingFraction: 0.84)
    /// Large, playful entrances (celebrations, onboarding).
    static let bouncy = Animation.spring(response: 0.55, dampingFraction: 0.62)
    /// Slow ambient movement.
    static let gentle = Animation.easeInOut(duration: 0.7)

    /// Count-up duration for numbers on the Today screen.
    static let countUpDuration: Double = 0.9
    /// Delay between label chips fading in.
    static let chipStagger: Double = 0.035
    /// The Undo window for sending.
    static let undoWindow: TimeInterval = 30

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `animation`, or a plain fade when Reduce Motion is on.
    static func resolved(_ animation: Animation, reduceMotion: Bool = Motion.reduceMotion) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : animation
    }

    /// Sent drafts slide out, new rows drop in.
    static func rowTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    static func popTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity)
    }
}

/// Run a state change with a Motion token (Reduce Motion aware).
@discardableResult
func withMotion<Result>(_ animation: Animation = Motion.standard, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.resolved(animation), body)
}

private struct MotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

/// Fades a view in after `delay` (label chips use this with a stagger).
private struct FadeInModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.85)
            .onAppear {
                guard !visible else { return }
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(Motion.standard.delay(delay)) { visible = true }
                }
            }
    }
}

extension View {
    func motion<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
        modifier(MotionAnimationModifier(animation: animation, value: value))
    }

    func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeInModifier(delay: delay))
    }
}
