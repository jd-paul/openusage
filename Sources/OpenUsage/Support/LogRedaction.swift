import Foundation

/// The redaction every `AppLog` line passes through before it reaches unified logging: JWTs, bare API
/// keys, `account=` values, and home or system paths are masked.
///
/// This is the last line of defence, not permission to log a credential. Nothing logs a URL's query,
/// a header, or a response body in the first place.
enum LogRedaction {
    static func redactLogMessage(_ message: String) -> String {
        message
            .replacing(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, with: "[REDACTED]")
            .replacing(/(?:sk-|pk-|api_|key_|secret_)[A-Za-z0-9_-]{12,}/, with: "[REDACTED]")
            .replacing(/account=[^,\s]+/, with: "account=[REDACTED]")
            .replacing(/\/(?:Users|home|opt|private|var|tmp|Applications)\/[^\s"')]+/, with: "[PATH]")
    }
}
