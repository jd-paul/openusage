import OSLog
import XCTest
@testable import OpenUsage

/// Each refresh pass's start and end reach unified logging at notice level, which macOS keeps on disk,
/// so `log show` finds them after the fact. Info lines live only in memory.
@MainActor
final class RefreshPassLogTests: XCTestCase {
    func testPassStartAndEndAreKeptOnDisk() async throws {
        let suiteName = "OpenUsageTests.RefreshPassLog.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetDataStore(
            registry: WidgetRegistry(providers: [], descriptors: []),
            providers: [],
            cache: ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots"),
            defaults: defaults
        )
        let logStore = try OSLogStore(scope: .currentProcessIdentifier)
        let since = logStore.position(date: Date().addingTimeInterval(-1))

        await store.refreshAll()

        let batchLines = try logStore.getEntries(at: since)
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "OpenUsage" && $0.category == "refresh" && $0.composedMessage.hasPrefix("[refresh] batch ") }
        XCTAssertTrue(batchLines.contains { $0.composedMessage.hasPrefix("[refresh] batch start (0 providers") })
        XCTAssertTrue(batchLines.contains { $0.composedMessage.hasPrefix("[refresh] batch end") })
        XCTAssertEqual(Set(batchLines.map(\.level)), [.notice])
    }
}
