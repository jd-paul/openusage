import Foundation

/// Latest normalized output for one provider refresh.
struct ProviderSnapshot: Hashable, Sendable, Codable {
    let providerID: String
    let displayName: String
    var plan: String?
    var lines: [MetricLine]
    var refreshedAt: Date
    /// Set only on a failed refresh: the message the provider's card shows. `lines` is empty then.
    var errorMessage: String?

    init(
        providerID: String,
        displayName: String,
        plan: String? = nil,
        lines: [MetricLine],
        refreshedAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.plan = plan
        self.lines = lines
        self.refreshedAt = refreshedAt
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
        refreshedAt: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: provider.id,
            displayName: provider.displayName,
            plan: plan,
            lines: lines,
            refreshedAt: refreshedAt
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
