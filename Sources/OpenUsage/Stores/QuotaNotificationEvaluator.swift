import Foundation

/// Owns the quota pace-notification subsystem: the per-metric dedup state and the fire/deliver/commit
/// decision. Split out of `WidgetDataStore` (which orchestrates refresh + resolves
/// `MetricLine`s) so the notification concern is self-contained. The store gathers each pass's enabled,
/// bounded, visible metrics and calls `evaluate`; delivery + the provider display name come in as
/// closures so this type stays independent of the store's providers.
///
/// Deduped per metric per reset window. No-data metrics never fire; bounded level-only metrics can fire
/// Almost Out, but not pace-based milestones. State for metrics not passed this pass is pruned, so
/// re-enabling/re-adding a metric starts fresh rather than carrying a stale "already fired" flag.
@MainActor
final class QuotaNotificationEvaluator {
    /// One enabled, bounded, visible metric for this pass, already resolved by the store.
    struct Metric {
        let key: String
        let providerID: String
        let data: WidgetData
    }

    private var notificationState: [String: NotificationState] = [:]

    /// Evaluate every metric for a quota pace milestone and deliver a notification for any that just
    /// crossed one, via `post` (id-prefix, title, subtitle, body → delivered?). `providerName` maps a
    /// provider id to its display name for the subtitle.
    func evaluate(
        metrics: [Metric],
        toggles: PaceNotificationToggles,
        now: Date,
        providerName: @MainActor (String) -> String,
        post: @MainActor (String, String, String, String) async -> Bool
    ) async {
        var nextState: [String: NotificationState] = [:]
        for metric in metrics {
            let key = metric.key
            let data = metric.data
            let state = data.meterState(now: now)
            let previous = notificationState[key] ?? NotificationState()
            let result = PaceNotificationLogic.transitions(
                state: state,
                fraction: data.remainingFraction,
                resetsAt: data.resetsAt,
                previous: previous,
                toggles: toggles
            )
            // Deliver each fired milestone, then commit dedup state only for the ones that actually
            // delivered. The logic doesn't mark milestones fired — that's done here, after delivery
            // succeeds, so a skipped/failed delivery (not authorized, or `add` errored) leaves the
            // milestone un-marked and the state advance reverted, re-firing on the next pass instead of
            // being lost for the rest of the reset window.
            var next = result.newState
            var paceDelivered = false
            var underDelivered = false
            for milestone in result.fire {
                let delivered = await deliver(milestone, data: data, providerID: metric.providerID,
                                              providerName: providerName, post: post)
                if delivered {
                    if milestone == .underTenPercent { underDelivered = true } else { paceDelivered = true }
                    next.firedMilestones.insert(milestone)
                }
            }
            if result.fire.contains(where: { $0 != .underTenPercent }) && !paceDelivered {
                next.previousBucket = previous.previousBucket
            }
            if result.fire.contains(.underTenPercent) && !underDelivered {
                next.wasUnderTenPercent = previous.wasUnderTenPercent
            }
            if !result.fire.isEmpty {
                AppLog.debug(.notifications, "\(key): \(previous.previousBucket) -> \(next.previousBucket), fired \(result.fire.map(\.rawValue)), delivered pace=\(paceDelivered) under10=\(underDelivered)")
            }
            nextState[key] = next
        }
        notificationState = nextState
    }

    /// Build and post one milestone notification. The title is the trigger name (matches the Settings
    /// row), the subtitle is "Provider Metric" so the user knows which quota worsened, and the body is
    /// the plain-language verdict. Title Case per AGENTS.md. Returns whether delivery succeeded.
    private func deliver(
        _ milestone: PaceMilestone,
        data: WidgetData,
        providerID: String,
        providerName: @MainActor (String) -> String,
        post: @MainActor (String, String, String, String) async -> Bool
    ) async -> Bool {
        let subtitle = "\(providerName(providerID)) \(data.title)"
        return await post("\(providerID).\(milestone.rawValue)", milestone.notificationTitle, subtitle, milestone.body)
    }
}
