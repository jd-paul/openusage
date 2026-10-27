import Foundation

/// Single source of truth for how often OpenUsage asks the providers.
///
/// The periodic refresh loop and the snapshot-cache TTL both read the cadence through here so they can
/// never disagree: the cache treats a snapshot as fresh for exactly one refresh interval, and the loop
/// re-fetches when that window elapses. The cadence is fixed — there's no user-facing control — so the
/// two always line up.
enum RefreshSetting {
    static let defaultMinutes = 5
    static let interval = TimeInterval(defaultMinutes * 60)

    /// The wait after an account's first failed refresh in a row; each further failure doubles it.
    static let failureBackoffBase = interval
    /// The longest wait between attempts on an account that keeps failing.
    static let failureBackoffCap: TimeInterval = 60 * 60
}
