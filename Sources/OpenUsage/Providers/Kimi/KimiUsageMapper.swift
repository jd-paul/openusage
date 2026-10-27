import Foundation

/// Builds metric lines from the Kimi coding-usage payload:
/// - the `limits[]` entry whose window is 300 minutes is the rolling five-hour session meter,
/// - the top-level `usage` object is the weekly quota meter (the shape Kimi's own `/usage` shows).
///
/// The endpoint is an undocumented internal API used by the Kimi Code CLI; the shapes below are the
/// ones QuotaWidget captured and fixture-tested, and they tolerate the field variants seen across
/// revisions (`used` vs `remaining`; `reset_at` epoch vs `resetAt` ISO vs `resetTime.seconds`).
/// The mapper is pure (no I/O) so it tests cleanly against sample payloads.
enum KimiUsageMapper {
    static let sessionPeriodMs = 5 * 60 * 60 * 1000
    static let weeklyPeriodMs = 7 * 24 * 60 * 60 * 1000

    /// `(plan, lines)` from one usage payload. Either meter may be absent from a given response
    /// (e.g. a plan without a weekly quota) — only what's present is mapped.
    static func map(_ body: Data, now: Date = Date()) throws -> (plan: String?, lines: [MetricLine]) {
        guard let root = ProviderParse.jsonObject(body) else {
            throw KimiUsageError.invalidResponse
        }
        var lines: [MetricLine] = []
        if let session = fiveHourLimit(in: root) {
            lines.append(try percentLine(session, label: "Session", periodMs: sessionPeriodMs, now: now))
        }
        if let usage = root["usage"] as? [String: Any] {
            lines.append(try percentLine(usage, label: "Weekly", periodMs: weeklyPeriodMs, now: now))
        }
        guard !lines.isEmpty else {
            throw KimiUsageError.invalidResponse
        }
        return (nil, lines)
    }

    /// The rolling five-hour limit: the `limits[]` entry whose window is 300 minutes. Its numbers
    /// live in `detail` when present, else on the entry itself. Shorter windows (e.g. a per-minute
    /// burst limit) and longer ones are ignored so they can't shadow the meter.
    static func fiveHourLimit(in root: [String: Any]) -> [String: Any]? {
        guard let limits = root["limits"] as? [[String: Any]] else { return nil }
        for item in limits {
            guard let window = item["window"] as? [String: Any],
                  ProviderParse.number(window["duration"]) == 300,
                  let unit = window["timeUnit"] as? String,
                  unit.uppercased().contains("MINUTE")
            else { continue }
            return (item["detail"] as? [String: Any]) ?? item
        }
        return nil
    }

    /// A percentage meter from a quota object. `used` wins over `remaining` (either satisfies);
    /// a missing reset is tolerated (the row just carries no countdown) but a missing limit is a
    /// malformed response — fail loudly rather than showing a bogus 0%.
    static func percentLine(_ object: [String: Any], label: String, periodMs: Int, now: Date) throws -> MetricLine {
        guard let limit = ProviderParse.number(object["limit"]), limit > 0 else {
            throw KimiUsageError.invalidResponse
        }
        let used: Double
        if let explicit = ProviderParse.number(object["used"]) {
            used = explicit
        } else if let remaining = ProviderParse.number(object["remaining"]) {
            used = limit - remaining
        } else {
            throw KimiUsageError.invalidResponse
        }
        let resetsAt = resetDate(in: object)
        // A reset already in the past marks the window as stale: keep the meter but drop the
        // countdown so the UI doesn't show a negative timer.
        let reset = resetsAt.flatMap { $0 > now ? $0 : nil }
        return .progress(
            label: label,
            used: min(max(used / limit * 100, 0), 100),
            limit: 100,
            format: .percent,
            resetsAt: reset,
            periodDurationMs: periodMs
        )
    }

    /// The window's reset instant. Across payload revisions the key has been `reset_at` (epoch
    /// seconds), `resetAt` (ISO-8601), and `resetTime`/`reset_time` (object with a `seconds`
    /// field, itself string or number) — all are honored.
    static func resetDate(in object: [String: Any]) -> Date? {
        for key in ["reset_at", "resetAt", "resetTime", "reset_time"] {
            guard let raw = object[key] else { continue }
            if let nested = raw as? [String: Any] {
                if let seconds = ProviderParse.number(nested["seconds"]) {
                    return Date(timeIntervalSince1970: seconds)
                }
                continue
            }
            if let seconds = ProviderParse.number(raw) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let string = raw as? String, let date = OpenUsageISO8601.date(from: string) {
                return date
            }
        }
        return nil
    }
}
