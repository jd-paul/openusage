import AppKit
import Observation

/// Single source of truth for the popover's transparency: the panel is opaque unless the secret-code
/// easter egg is on, and the egg yields to the live macOS accessibility flags. Both SwiftUI (via
/// `partyActive`) and the AppKit panel (`StatusItemController`) read this one store, so the SwiftUI
/// surface and the window can't drift apart.
@MainActor
@Observable
final class PopoverTransparencyStore {
    /// Ephemeral easter-egg state. Never persisted: it clears on quit, but survives panel open/close
    /// within a run, so the only way out is re-typing the code.
    private(set) var secretCodeActive = false

    /// Whether the popover is currently on-screen (ordered-on). Runtime-transient like `secretCodeActive`
    /// — never persisted. Set by `StatusItemController` at its `showPanel`/`hidePanel` chokepoints (the
    /// authoritative on-screen state, flipped synchronously with `makeKeyAndOrderFront`/`orderOut`) and
    /// read by the SwiftUI egg via `\.popoverIsVisible` to **mount** its animation loops only while
    /// visible — so a closed popover with the egg still active spends no CPU animating. Deliberately NOT
    /// derived from occlusion or window key state: a `.canJoinAllSpaces` panel is briefly fully occluded
    /// mid Space-switch while still following the user on-screen, so an occlusion gate would freeze the
    /// animation on the very panel the user is now looking at.
    private(set) var popoverShown = false

    /// Live system accessibility flags. Read from `NSWorkspace` and refreshed on the change notification.
    private(set) var reduceTransparency: Bool
    private(set) var increaseContrast: Bool

    @ObservationIgnored private var accessibilityObservation: Task<Void, Never>?

    init(
        reduceTransparency: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
        increaseContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    ) {
        // The flags default to the live `NSWorkspace` values (production) but are injectable so tests can
        // pin them and exercise the accessibility clamp deterministically, independent of the test host.
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        startObservingAccessibility()
    }

    deinit { accessibilityObservation?.cancel() }

    /// Toggled by `TooMuchTransparencyKeyReader` when the full code is entered — so a second entry turns
    /// the egg off.
    func toggleSecretCode() {
        secretCodeActive.toggle()
        AppLog.info(.statusItem, "Too-much-transparency egg \(secretCodeActive ? "enabled" : "disabled")")
    }

    /// Flips the on-screen flag from `StatusItemController`'s show/hide chokepoints. Guards on change so a
    /// redundant set doesn't churn observers. Orthogonal to `partyActive`, so toggling it re-renders only
    /// the SwiftUI egg's mount gate, never the AppKit backdrop crossfade.
    func setPopoverShown(_ shown: Bool) {
        guard shown != popoverShown else { return }
        popoverShown = shown
    }

    /// Whether the panel and the SwiftUI surface render the party. Reduce Transparency and Increase
    /// Contrast are accessibility *needs*, not preferences, so they clamp the panel to opaque first: the
    /// egg being a hidden, user-invoked cheat code doesn't make overriding an accessibility setting safe.
    var partyActive: Bool {
        secretCodeActive && !reduceTransparency && !increaseContrast
    }

    /// Accessibility display options post to `NSWorkspace`'s OWN notification center (never `.default`).
    /// The notification carries no payload, so we ignore it and re-read the flags on the main actor —
    /// which also sidesteps the non-`Sendable` `Notification` under Swift 6 strict concurrency.
    private func startObservingAccessibility() {
        let center = NSWorkspace.shared.notificationCenter
        let name = NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        accessibilityObservation = Task { [weak self] in
            for await _ in center.notifications(named: name) {
                self?.refreshAccessibilityFlags()
            }
        }
    }

    private func refreshAccessibilityFlags() {
        let workspace = NSWorkspace.shared
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
    }
}
