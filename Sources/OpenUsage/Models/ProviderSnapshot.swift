import Foundation

/// Latest normalized output for one provider refresh.
struct ProviderSnapshot: Hashable, Sendable, Codable {
    let providerID: String
    let displayName: String
    var plan: String?
    var lines: [MetricLine]
    var refreshedAt: Date
    /// A soft, non-blocking notice carried on a *successful* snapshot — e.g. Claude's "Re-login for live
    /// usage" when the saved login lacks the `user:profile` scope. Distinct from an error snapshot: the
    /// refresh succeeded and partial data (spend tiles) still loads, so this surfaces as the provider
    /// header's orange triangle rather than blanking the provider. Cached with the snapshot; cleared on
    /// the next refresh when the condition resolves.
    var warning: String?
    /// Set only on a failed refresh: the message the provider's card shows. `lines` is empty then.
    var errorMessage: String?

    init(
        providerID: String,
        displayName: String,
        plan: String? = nil,
        lines: [MetricLine],
        refreshedAt: Date = Date(),
        warning: String? = nil,
        errorMessage: String? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.plan = plan
        self.lines = lines
        self.refreshedAt = refreshedAt
        self.warning = warning
        self.errorMessage = errorMessage
    }

    func line(label: String) -> MetricLine? {
        lines.first { $0.label == label }
    }

    /// The success-path counterpart to `error(provider:message:)`: derives `providerID`/`displayName`
    /// from the provider so account runtimes build their snapshots consistently.
    static func make(
        provider: Provider,
        plan: String?,
        lines: [MetricLine],
        refreshedAt: Date,
        warning: String? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: provider.id,
            displayName: provider.displayName,
            plan: plan,
            lines: lines,
            refreshedAt: refreshedAt,
            warning: warning
        )
    }

    /// Build an error snapshot straight from a caught error: the message is the error's user-facing
    /// `localizedDescription`.
    static func error(provider: Provider, error: Error) -> ProviderSnapshot {
        Self.error(provider: provider, message: error.localizedDescription)
    }

    static func error(provider: Provider, message: String) -> ProviderSnapshot {
        ProviderSnapshot(providerID: provider.id, displayName: provider.displayName, lines: [], errorMessage: message)
    }
}
