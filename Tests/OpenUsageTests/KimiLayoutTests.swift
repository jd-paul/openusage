import XCTest
@testable import OpenUsage

/// Locks Kimi's default metric placement (consistent with Z.ai, the closest analog — two quota
/// windows): Session and Weekly stay above the fold and both pin to the menu bar out of the box.
final class KimiLayoutTests: XCTestCase {
    private let metrics = ["kimi.session", "kimi.weekly"]

    func testAllMetricsEnabledByDefault() {
        for id in metrics {
            XCTAssertTrue(DefaultLayout.metricIDs.contains(id), "\(id) should be enabled by default")
        }
    }

    func testQuotaMetersStayAboveTheFold() {
        for id in metrics {
            XCTAssertFalse(DefaultLayout.expandedMetricIDs.contains(id), "\(id) should stay above the fold")
        }
    }

    func testBothQuotaMetersPinnedByDefault() {
        for id in metrics {
            XCTAssertTrue(DefaultLayout.pinnedMetricIDs.contains(id), "\(id) should pin to the menu bar by default")
        }
    }
}
