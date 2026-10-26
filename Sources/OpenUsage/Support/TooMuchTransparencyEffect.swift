import SwiftUI

extension View {
    /// The "too much transparency" easter egg, applied as one stable modifier so enabling and disabling
    /// **crossfade** (a ~0.55s ease) instead of snapping. A loud but **readable** party: a vivid churning
    /// gradient fills the popover behind the content and a glowing rim rotates around the edge, while the
    /// content stays crisp on frosted cards (no blur over text). Meter bars and provider marks join in via
    /// the `popoverPartyMode` environment flag. Identity while off.
    func tooMuchTransparency(active: Bool) -> some View {
        modifier(TooMuchTransparencyModifier(active: active))
    }
}

/// Shared party palette — a cocktail of hot pink, violet, teal, and amber.
private let partyColors: [Color] = [
    Color(red: 1.00, green: 0.32, blue: 0.74),
    Color(red: 0.62, green: 0.40, blue: 1.00),
    Color(red: 0.30, green: 0.85, blue: 0.95),
    Color(red: 1.00, green: 0.72, blue: 0.30),
    Color(red: 1.00, green: 0.32, blue: 0.74),
]

/// One stable modifier whose layers come and go by `active`. The `.animation(value:)` plus per-layer
/// `.transition(.opacity)` is what makes toggling the egg fade in and out (the AppKit backdrop crossfades
/// on the same ~0.55s ease, driven by `StatusItemController`).
private struct TooMuchTransparencyModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if active { PartyBackdrop().transition(.opacity) }
            }
            .overlay {
                if active { PartyRim().transition(.opacity).allowsHitTesting(false) }
            }
            .environment(\.popoverPartyMode, active)
            .animation(.easeInOut(duration: 0.55), value: active)
    }
}

/// A vivid, slowly churning gradient that **tints** the popover, sitting behind the (frosted, readable)
/// content. It's deliberately semi-transparent so the behind-window vibrancy backdrop — the blurred
/// desktop — shows through and blends with the party colors, rather than an opaque wall that hides it.
/// (A SwiftUI `blendMode` can't composite against the AppKit vibrancy view behind the host, so the
/// desktop only blends through via alpha — hence the reduced opacity rather than a blend mode.)
private struct PartyBackdrop: View {
    var body: some View {
        // Churning clock mounts only while the popover is on-screen (see `VisibilityGatedTimeline`).
        VisibilityGatedTimeline { t in gradient(at: t) }
    }

    private func gradient(at t: TimeInterval) -> some View {
        ZStack {
            AngularGradient(colors: partyColors, center: .center, angle: .degrees(t * 28))
                .opacity(0.5)   // translucent tint, so the blurred desktop blends through the colors
            RadialGradient(
                colors: [Color.white.opacity(0.15), .clear],
                center: UnitPoint(x: 0.5 + cos(t * 0.5) * 0.3, y: 0.5 + sin(t * 0.6) * 0.3),
                startRadius: 0,
                endRadius: 240
            )
            .blendMode(.plusLighter)
        }
    }
}

/// A glowing rim that rotates around the popover edge — pure party, never over the text.
private struct PartyRim: View {
    var body: some View {
        VisibilityGatedTimeline { t in rim(at: t) }
    }

    private func rim(at t: TimeInterval) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(
                AngularGradient(colors: partyColors, center: .center, angle: .degrees(-t * 36)),
                lineWidth: 2.5
            )
            .shadow(color: Color(red: 1, green: 0.4, blue: 0.85).opacity(0.7), radius: 7)
    }
}
