import Foundation

/// How a bounded `.progress` row formats its numbers: a percent meter, a dollar meter, or a count with
/// its unit word.
enum ProgressFormat: Hashable, Sendable, Codable {
    case percent
    case dollars
    case count(suffix: String)

    var metricKind: MetricKind {
        switch self {
        case .percent:
            return .percent
        case .dollars:
            return .dollars
        case .count:
            return .count
        }
    }
}

/// Provider output normalized into a small app-owned vocabulary. Cached as JSON with its snapshot
/// (`ProviderSnapshotCache`), so a change to this shape bumps the cache key.
enum MetricLine: Hashable, Sendable, Codable {
    /// An unbounded row carrying one or more raw numbers (see `MetricValue`) — the preferred shape for
    /// numeric rows. The number is the source of truth; formatting and which value(s) to show happen at
    /// the display edge, so the menu bar never has to re-parse a finished string.
    ///
    /// `expiriesAt` carries zero or more future expiry instants the row lists in its hover popover —
    /// used for the Limit Resets row ("2 available", with each reset's expiry on its own line).
    /// Carried as raw `Date`s (not baked strings) so they count down on the popover's clock tick and honor
    /// the global relative/absolute reset mode, like a bounded row's reset countdown.
    case values(label: String, values: [MetricValue], expiriesAt: [Date] = [])
    case progress(
        label: String,
        used: Double,
        limit: Double,
        format: ProgressFormat,
        resetsAt: Date? = nil,
        periodDurationMs: Int? = nil
    )
    /// A short status in the value column, e.g. Grok's "Pay as you go" cap.
    case badge(label: String, text: String)

    var label: String {
        switch self {
        case .progress(let label, _, _, _, _, _),
             .values(let label, _, _),
             .badge(let label, _):
            return label
        }
    }
}
