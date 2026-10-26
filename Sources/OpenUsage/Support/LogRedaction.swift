import Foundation

/// The redaction every `AppLog` line passes through before it reaches unified logging: JWTs, bare API
/// keys, `account=` values, and home or system paths are masked. Pure, `Sendable`, no I/O.
///
/// This is the last line of defence, not permission to log a credential. Nothing logs a URL's query,
/// a header, or a response body in the first place.
enum LogRedaction {
    /// Redact a sensitive value to `first4...last4`, or `[REDACTED]` when it is too short to mask
    /// safely.
    static func redactValue(_ value: String) -> String {
        let chars = Array(value)
        if chars.count <= 12 {
            return "[REDACTED]"
        }
        let first4 = String(chars.prefix(4))
        let last4 = String(chars.suffix(4))
        return "\(first4)...\(last4)"
    }

    /// Lightweight redaction for free-form log messages: JWT, API keys, account values, then paths.
    static func redactLogMessage(_ message: String) -> String {
        var result = message
        result = replaceAll(jwtRegex, in: result) { redactValue($0) }
        result = replaceAll(apiKeyBareRegex, in: result) { redactValue($0) }
        result = replaceAccountEq(in: result)
        result = pathRegex.stringByReplacingMatches(
            in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "[PATH]"
        )
        return result
    }

    private static let jwtRegex = makeRegex(#"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#)
    private static let apiKeyBareRegex = makeRegex(#"(sk-|pk-|api_|key_|secret_)[A-Za-z0-9_-]{12,}"#)
    private static let accountRegex = makeRegex(#"(account=)([^,\s]+)"#)
    private static let pathRegex = makeRegex(#"(/(?:Users|home|opt|private|var|tmp|Applications)/[^\s"')]+)"#)

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        // The patterns are static literals; a failure here is a programmer error, so fail loudly rather
        // than silently disabling redaction.
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            fatalError("LogRedaction: invalid regex pattern: \(pattern)")
        }
        return regex
    }

    /// Replace every full match of `regex` in `input` using `transform` on the matched substring.
    /// Walks matches in reverse so earlier ranges stay valid as later ones are replaced.
    private static func replaceAll(
        _ regex: NSRegularExpression,
        in input: String,
        transform: (String) -> String
    ) -> String {
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        guard !matches.isEmpty else { return input }
        var result = input
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }

    /// The `account=<value>` pass: keep the `account=` prefix, redact only the value (group 2).
    private static func replaceAccountEq(in input: String) -> String {
        let matches = accountRegex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        guard !matches.isEmpty else { return input }
        var result = input
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range, in: result),
                  let prefixRange = Range(match.range(at: 1), in: result),
                  let valueRange = Range(match.range(at: 2), in: result)
            else { continue }
            let prefix = String(result[prefixRange])
            let value = String(result[valueRange])
            result.replaceSubrange(fullRange, with: "\(prefix)\(redactValue(value))")
        }
        return result
    }
}
