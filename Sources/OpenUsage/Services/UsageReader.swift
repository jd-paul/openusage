import Foundation

public struct UsageReadResult: Sendable {
    /// The limits envelope (`LimitsEnvelope`), always complete JSON.
    public let data: Data
    /// False when no requested account has a cached fetch yet.
    public let hasSnapshots: Bool
}

public enum UsageReaderError: Error, Sendable {
    case unknownProvider(String)
}

/// One-shot read of the usage the app last fetched, for the `openusage` command. It reads the app's
/// accounts and snapshot cache from the app's defaults domain and prints them; it never touches the
/// Keychain and never refreshes, so it needs neither the app running nor any credential.
@MainActor
public struct UsageReader {
    private let defaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        defaults = userDefaults
    }

    /// `providerID` names accounts by plain string matching: an exact card id names that account, a
    /// provider kind (`claude`, `codex`) names every account of that kind, and anything else throws
    /// `unknownProvider`. `nil` reads every account.
    public func read(providerID: String? = nil) throws -> UsageReadResult {
        let accounts = AccountStore.load(from: defaults)
        let registry = WidgetRegistry(
            providers: accounts.map(AccountProviderRuntime.provider(for:)),
            descriptors: accounts.flatMap(AccountProviderRuntime.widgetDescriptors(for:))
        )
        var providerIDs = accounts.map(\.cardID)
        if let token = providerID?.lowercased() {
            providerIDs = providerIDs.filter { $0 == token || Account.kindScopedID($0) == token }
            guard !providerIDs.isEmpty else { throw UsageReaderError.unknownProvider(token) }
        }
        let snapshots = ProviderSnapshotCache(userDefaults: defaults).loadSnapshots(providerIDs: providerIDs)
        let data = LimitsEnvelope.encode(LimitsEnvelope.Input(
            providerIDs: providerIDs,
            snapshots: snapshots,
            limitDescriptors: registry.limitDescriptorsByProvider
        ))
        return UsageReadResult(data: data, hasSnapshots: !snapshots.isEmpty)
    }
}
