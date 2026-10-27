import CoreGraphics
import Foundation

/// Single source of truth for how often OpenUsage asks the providers. Every cadence, wait and minimum
/// lives here so they are easy to tune together.
///
/// The periodic refresh loop and the snapshot-cache TTL both read the cadence through here so they can
/// never disagree: the cache treats a snapshot as fresh for exactly one refresh interval, and the loop
/// re-fetches when that window elapses. There's no user-facing control.
enum RefreshSetting {
    static let defaultMinutes = 5
    /// The pass cadence while the user is at the Mac or the popover is open.
    static let interval = TimeInterval(defaultMinutes * 60)
    /// The pass cadence once the Mac has had no input for `idleAfter`.
    static let idleInterval: TimeInterval = 15 * 60
    /// How long the Mac goes without keyboard, mouse or trackpad input before it counts as idle.
    static let idleAfter: TimeInterval = 10 * 60
    /// How often the waiting loop rechecks whether a pass is due, so a user coming back to an idle Mac
    /// gets a pass within this long rather than at the end of the idle interval.
    static let loopCheck: TimeInterval = 60
    /// Opening the popover refreshes every account whose numbers are older than this.
    static let popoverStaleAge = interval

    /// The wait after an account's first failed refresh in a row; each further failure doubles it.
    static let failureBackoffBase = interval
    /// The longest wait between attempts on an account that keeps failing.
    static let failureBackoffCap: TimeInterval = 60 * 60

    /// How long a read that rarely changes (a plan name, Codex's reset-credit list) is reused before it
    /// is asked again (see `SecondaryRead`).
    static let secondaryReadInterval: TimeInterval = 60 * 60

    /// A manual refresh (⌘R) skips an account fetched less than this long ago.
    static let manualRefreshMinimum: TimeInterval = 30

    /// The pass cadence for the user's current state: `interval` while they're at the Mac or the popover
    /// is open, `idleInterval` once there has been no input for `idleAfter`.
    static func passInterval(secondsSinceInput: TimeInterval, popoverOpen: Bool) -> TimeInterval {
        popoverOpen || secondsSinceInput < idleAfter ? interval : idleInterval
    }

    /// The cadence after a fetch made now: the one the loop will be on at its next pass if no input
    /// arrives before then. It leaves the popover out, so an account fetched while the popover is open on
    /// an idle Mac reads fresh longer than it needs to, never stale early.
    static func expectedInterval(secondsSinceInput: TimeInterval) -> TimeInterval {
        passInterval(secondsSinceInput: secondsSinceInput + interval, popoverOpen: false)
    }

    /// Seconds since the last keyboard, mouse or trackpad event in this login session. Reading it needs
    /// no permission (unlike an event tap).
    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
