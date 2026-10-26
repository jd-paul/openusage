import XCTest
@testable import OpenUsage

/// The never-log-secrets guard on the redaction every log line passes through.
final class LogRedactionTests: XCTestCase {
    func testRedactValueShortIsFullyRedacted() {
        XCTAssertEqual(LogRedaction.redactValue("short"), "[REDACTED]")
        // Exactly 12 chars is still "short" (<= 12).
        XCTAssertEqual(LogRedaction.redactValue("abcdefghijkl"), "[REDACTED]")
    }

    func testRedactValueLongMasksEnds() {
        XCTAssertEqual(LogRedaction.redactValue("sk-1234567890abcdef"), "sk-1...cdef")
        XCTAssertEqual(LogRedaction.redactValue("abcdefghijklm"), "abcd...jklm")
    }

    func testRedactLogMessageJWTAndBareApiKey() {
        let msg = "token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U key=sk-1234567890abcdef"
        let redacted = LogRedaction.redactLogMessage(msg)
        XCTAssertFalse(redacted.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"), redacted)
        XCTAssertFalse(redacted.contains("sk-1234567890abcdef"), redacted)
    }

    func testRedactLogMessageAccountEqAndPaths() {
        let msg = "keychain read: service=Claude Code-credentials, account=rebers path=/opt/homebrew/bin/bunx home=/Users/rebers/.claude"
        let redacted = LogRedaction.redactLogMessage(msg)
        XCTAssertFalse(redacted.contains("account=rebers"), redacted)
        XCTAssertFalse(redacted.contains("/opt/homebrew/bin/bunx"), redacted)
        XCTAssertFalse(redacted.contains("/Users/rebers/.claude"), redacted)
        XCTAssertTrue(redacted.contains("account=[REDACTED]"), redacted)
        XCTAssertTrue(redacted.contains("[PATH]"), redacted)
    }
}
