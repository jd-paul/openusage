import Foundation
import os

struct ProviderSnapshotCache {
    private struct Payload: Codable {
        var snapshots: [String: ProviderSnapshot]
        /// The app version that saved the blob. Snapshots from another version are shown at launch but
        /// never count as fresh, since that version may have read different metrics (#697).
        var appVersion: String?
    }

    /// In-memory mirror of the persisted blob. Reads (`snapshot`, `loadSnapshots`, and the read inside
    /// `store`) hit this instead of re-decoding the whole all-providers JSON from `UserDefaults` on
    /// every call — a refresh pass otherwise paid O(N) full decodes (plus O(N) encodes) per pass on the
    /// MainActor. The blob is decoded at most once per cache instance (first access); `store` and
    /// `remove` write through it. Lock-backed so the value-type cache memoizes across calls and stays
    /// safe to share.
    private let memo = OSAllocatedUnfairLock<Payload?>(initialState: nil)

    /// Provider IDs whose snapshot may count as fresh: every one written by `store` this session, and at
    /// launch every one this same app version saved. So a relaunch inside the refresh interval costs no
    /// requests, while an update refetches on its first pass instead of showing what the old version read
    /// (#697). Lock-backed for the same reason as `memo`: the value-type cache shares it across copies
    /// and stays safe.
    private let trusted = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let appVersion: String
    /// A trusted snapshot stays fresh for exactly one refresh interval after it was fetched, then expires
    /// so the periodic loop refetches on schedule. Tests inject a fixed TTL for a deterministic window.
    private let ttl: TimeInterval
    private let now: () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "openusage.providerSnapshots.v11",
        appVersion: String = AppInfo.version,
        ttl: TimeInterval = RefreshSetting.interval,
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.appVersion = appVersion
        self.ttl = ttl
        self.now = now
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Every stored snapshot for the given providers, including expired ones. Display uses this
    /// (stale-while-revalidate: last-known values keep showing while a refresh runs); refresh gating
    /// still goes through the TTL-checked `snapshot(providerID:)`.
    func loadSnapshots(providerIDs: [String]) -> [String: ProviderSnapshot] {
        let providerIDSet = Set(providerIDs)
        let loaded = loadPayload().snapshots.filter { providerID, _ in
            providerIDSet.contains(providerID)
        }
        AppLog.debug(.cache, "loaded \(loaded.count) snapshots from disk")
        return loaded
    }

    func snapshot(providerID: String) -> ProviderSnapshot? {
        let snapshot = loadPayload().snapshots[providerID]
        guard let snapshot else { return nil }
        // Fresh means trusted (written this session, or saved by this app version) and fetched less than
        // one TTL ago. A clock that went backwards never makes a snapshot fresh.
        let isTrusted = trusted.withLock { $0.contains(providerID) }
        let age = now().timeIntervalSince(snapshot.refreshedAt)
        let fresh = isTrusted && (0..<ttl).contains(age)
        let reason = !isTrusted ? "stale (saved by another app version)"
            : fresh ? "fresh" : "stale"
        AppLog.debug(.cache, "\(providerID) staleness \(Int(age))s vs ttl \(Int(ttl))s -> \(reason)")
        return fresh ? snapshot : nil
    }

    /// Records a successful snapshot and writes it through to `UserDefaults`.
    func store(_ snapshot: ProviderSnapshot) {
        guard snapshot.errorMessage == nil else {
            AppLog.debug(.cache, "skip write \(snapshot.providerID) (error snapshot)")
            return
        }
        AppLog.debug(.cache, "write \(snapshot.providerID)")
        var payload = loadPayload()
        trusted.withLock { _ = $0.insert(snapshot.providerID) }
        payload.snapshots[snapshot.providerID] = snapshot
        payload.appVersion = appVersion
        save(payload)
    }

    /// Drops the stored snapshots of removed accounts.
    func remove(providerIDs: Set<String>) {
        guard !providerIDs.isEmpty else { return }
        var payload = loadPayload()
        payload.snapshots = payload.snapshots.filter { !providerIDs.contains($0.key) }
        trusted.withLock { $0.subtract(providerIDs) }
        save(payload)
    }

    private func loadPayload() -> Payload {
        if let mirror = memo.withLock({ $0 }) { return mirror }
        // First access only: decode the persisted blob once, then mirror it. (Decoding outside the
        // lock keeps `self` out of the `@Sendable` closure; cache access is MainActor-serialized in
        // production, so the worst a race could do is decode twice into the same value — harmless.)
        let loaded = decodeStoredPayload()
        if loaded.appVersion == appVersion {
            trusted.withLock { $0.formUnion(loaded.snapshots.keys) }
        }
        memo.withLock { $0 = loaded }
        return loaded
    }

    private func decodeStoredPayload() -> Payload {
        // No stored data is the legitimate first-launch / cleared-cache case — recover to empty
        // silently. Data present but undecodable is a real problem (post-upgrade schema drift, a
        // half-written blob, a manual `defaults` edit): fail loudly, then recover to empty. A silent
        // drop here empties ALL providers' caches at once and feeds the refresh storm. Mirrors the
        // loud `save` path above. Runs at most once per cache instance (then memoized).
        guard let data = userDefaults.data(forKey: storageKey) else {
            return Payload(snapshots: [:])
        }
        do {
            return try decoder.decode(Payload.self, from: data)
        } catch {
            AppLog.warn(.cache, "cache decode failed, dropping stored snapshots: \(error.localizedDescription)")
            return Payload(snapshots: [:])
        }
    }

    private func save(_ payload: Payload) {
        // Update the in-memory mirror first so subsequent reads see this write even if the encode
        // below fails (the running session stays correct; only persistence is best-effort).
        memo.withLock { $0 = payload }
        // Fail loudly: a swallowed encode error would silently drop a snapshot from the persisted
        // cache. No behavior change (the write is still best-effort), but the failure is now visible.
        do {
            let data = try encoder.encode(payload)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            AppLog.warn(.cache, "encode failed, snapshot not persisted: \(error.localizedDescription)")
        }
    }
}
