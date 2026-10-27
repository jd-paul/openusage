import XCTest
@testable import OpenUsage

/// Verifies the Swift mapper against the response shape QuotaWidget captured and fixture-tested from
/// the real `api.kimi.com/coding/v1/usages` endpoint, plus the field variants seen across revisions.
/// The mapper is pure; these tests feed sample payloads and check the resulting metric lines.
final class KimiUsageMapperTests: XCTestCase {
    /// The fixture from QuotaWidget's `kimi_usage.json`: a 60-minute burst limit that must be
    /// ignored, the 300-minute (5-hour) session window, and the top-level weekly usage object.
    private let fixture = #"""
    {
      "usage": {"limit": 1000, "remaining": 920, "resetTime": {"seconds": "1781600000"}},
      "limits": [
        {"window": {"duration": 60, "timeUnit": "MINUTE"},
         "detail": {"limit": 100, "remaining": 90, "resetAt": "2026-06-11T13:00:00Z"}},
        {"window": {"duration": 300, "timeUnit": "MINUTE"},
         "detail": {"limit": 100, "used": 34, "reset_at": 1781190000}}
      ]
    }
    """#

    /// A "now" between the two fixture resets: the session reset (1781190000) is already stale and
    /// must be dropped, while the weekly reset (1781600000) stays a live countdown.
    private let now = Date(timeIntervalSince1970: 1_781_300_000)

    func testMapsFixtureResponseToSessionAndWeekly() throws {
        let mapped = try KimiUsageMapper.map(Data(fixture.utf8), now: now)

        let session = try XCTUnwrap(progress(mapped.lines, "Session"))
        XCTAssertEqual(session.used, 34, accuracy: 0.001)
        XCTAssertEqual(session.limit, 100, accuracy: 0.001)
        XCTAssertEqual(session.period, 5 * 60 * 60 * 1000)
        XCTAssertNil(session.resetsAt, "a past reset drops the countdown instead of showing a negative timer")

        let weekly = try XCTUnwrap(progress(mapped.lines, "Weekly"))
        XCTAssertEqual(weekly.used, 8, accuracy: 0.001)
        XCTAssertEqual(weekly.period, 7 * 24 * 60 * 60 * 1000)
        XCTAssertEqual(weekly.resetsAt, Date(timeIntervalSince1970: 1_781_600_000))
    }

    func testResetVariantsAcrossPayloadRevisions() throws {
        let future = Int(now.timeIntervalSince1970) + 3600
        let cases: [String] = [
            #"{"limits": [], "usage": {"limit": 100, "used": 10, "reset_at": \#(future)}}"#,
            #"{"limits": [], "usage": {"limit": 100, "used": 10, "resetAt": "2026-12-31T00:00:00Z"}}"#,
            #"{"limits": [], "usage": {"limit": 100, "used": 10, "resetTime": {"seconds": "\#(future)"}}}"#,
            #"{"limits": [], "usage": {"limit": 100, "used": 10, "reset_time": \#(future)}}"#,
        ]
        for json in cases {
            let mapped = try KimiUsageMapper.map(Data(json.utf8), now: now)
            let weekly = try XCTUnwrap(progress(mapped.lines, "Weekly"), json)
            XCTAssertNotNil(weekly.resetsAt, json)
        }
    }

    func testWeeklyPercentageComesFromUsedOrRemaining() throws {
        let future = Int(now.timeIntervalSince1970) + 3600
        let fromUsed = #"{"limits": [], "usage": {"limit": 500, "used": 125, "reset_at": \#(future)}}"#
        let fromRemaining = #"{"limits": [], "usage": {"limit": 500, "remaining": 375, "reset_at": \#(future)}}"#
        for json in [fromUsed, fromRemaining] {
            let mapped = try KimiUsageMapper.map(Data(json.utf8), now: now)
            XCTAssertEqual(try XCTUnwrap(progress(mapped.lines, "Weekly")).used, 25, accuracy: 0.001, json)
        }
    }

    func testAbsentWindowsMapIndependently() throws {
        let future = Int(now.timeIntervalSince1970) + 3600
        let sessionOnly = #"{"limits": [{"window": {"duration": 300, "timeUnit": "MINUTE"}, "detail": {"limit": 10, "used": 1, "reset_at": \#(future)}}]}"#
        let weeklyOnly = #"{"limits": [], "usage": {"limit": 10, "used": 1, "reset_at": \#(future)}}"#

        let sessionMapped = try KimiUsageMapper.map(Data(sessionOnly.utf8), now: now)
        XCTAssertEqual(sessionMapped.lines.map(\.label), ["Session"])

        let weeklyMapped = try KimiUsageMapper.map(Data(weeklyOnly.utf8), now: now)
        XCTAssertEqual(weeklyMapped.lines.map(\.label), ["Weekly"])
    }

    func testNeitherWindowThrowsInvalidResponse() {
        XCTAssertThrowsError(try KimiUsageMapper.map(#"{"limits": []}"#.data(using: .utf8)!, now: now)) { error in
            XCTAssertEqual(error as? KimiUsageError, .invalidResponse)
        }
    }

    func testNonFiveHourWindowsAreIgnored() throws {
        let future = Int(now.timeIntervalSince1970) + 3600
        let json = #"""
        {"limits": [
          {"window": {"duration": 60, "timeUnit": "MINUTE"}, "detail": {"limit": 100, "used": 50, "reset_at": \#(future)}},
          {"window": {"duration": 1440, "timeUnit": "MINUTE"}, "detail": {"limit": 100, "used": 50, "reset_at": \#(future)}}
        ], "usage": {"limit": 100, "used": 10, "reset_at": \#(future)}}
        """#
        let mapped = try KimiUsageMapper.map(Data(json.utf8), now: now)
        XCTAssertEqual(mapped.lines.map(\.label), ["Weekly"])
    }

    func testPercentageIsClamped() throws {
        let future = Int(now.timeIntervalSince1970) + 3600
        let json = #"{"limits": [], "usage": {"limit": 100, "used": 250, "reset_at": \#(future)}}"#
        let mapped = try KimiUsageMapper.map(Data(json.utf8), now: now)
        XCTAssertEqual(try XCTUnwrap(progress(mapped.lines, "Weekly")).used, 100, accuracy: 0.001)
    }

    func testMissingNumbersThrowInsteadOfSilentlyZeroing() {
        let noLimit = #"{"limits": [], "usage": {"used": 10}}"#
        let noUsage = #"{"limits": [], "usage": {"limit": 10}}"#
        for json in [noLimit, noUsage] {
            XCTAssertThrowsError(try KimiUsageMapper.map(Data(json.utf8), now: now)) { error in
                XCTAssertEqual(error as? KimiUsageError, .invalidResponse)
            }
        }
    }

    func testSessionNumbersOnTheEntryItselfWithoutDetail() throws {
        let future = Int(now.timeIntervalSince1970) + 3600
        let json = #"{"limits": [{"window": {"duration": 300, "timeUnit": "MINUTE"}, "limit": 40, "used": 10, "reset_at": \#(future)}]}"#
        let mapped = try KimiUsageMapper.map(Data(json.utf8), now: now)
        let session = try XCTUnwrap(progress(mapped.lines, "Session"))
        XCTAssertEqual(session.used, 25, accuracy: 0.001)
    }

    private func progress(_ lines: [MetricLine], _ label: String) -> (used: Double, limit: Double, period: Int?, resetsAt: Date?)? {
        guard case .progress(_, let used, let limit, _, let resetsAt, let period, _) = lines.first(where: { $0.label == label }) else {
            return nil
        }
        return (used, limit, period, resetsAt)
    }
}
