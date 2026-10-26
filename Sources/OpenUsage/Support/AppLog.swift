import Foundation
import os

/// Subsystem tags that prefix every log line, keeping lines grep-friendly (`[refresh]`, `[cache]`,
/// `[plugin:claude]`, …). The raw value is the bracketed text and the `os.Logger` category.
enum LogTag: String, Sendable {
    case refresh
    case cache
    case http
    case auth
    case menubar
    case updates
    case config
    case statusItem = "statusitem"
    case lifecycle
    case notifications

    /// Compound `[plugin:<id>]` / `[auth:<id>]` tags for per-provider lines.
    static func plugin(_ id: String) -> String { "plugin:\(id)" }
    static func auth(_ id: String) -> String { "auth:\(id)" }
}

/// The one logging facility: unified logging only, one `os.Logger` per category under the
/// `OpenUsage` subsystem. Read lines with Console or
/// `log stream --predicate 'subsystem == "OpenUsage"' --info`.
///
/// Each call runs the message through `LogRedaction.redactLogMessage` as a lightweight last line of
/// defense before it reaches the logger. `redactLogMessage` is URL/body-unaware: any call site that
/// logs a URL or response body MUST pre-redact it via `LogRedaction.redactURL` / `bodyPreview`.
///
/// Debug lines are compiled out of release builds before their message is built, so a `debug` call
/// on a hot path (`[cache]`, `[http]`) costs nothing there; a debug build keeps them.
enum AppLog {
    private enum Level {
        case error, warn, info, debug

        var osType: OSLogType {
            switch self {
            case .error: .error
            case .warn: .default
            case .info: .info
            case .debug: .debug
            }
        }
    }

    /// Per-category `os.Logger` cache, guarded by a lock so any isolation can log.
    private static let loggerLock = NSLock()
    private nonisolated(unsafe) static var loggers: [String: Logger] = [:]

    /// Emit one startup line. Call first at launch, before any other subsystem logs.
    static func bootstrap() {
        info(.config, "OpenUsage v\(AppInfo.version) starting")
    }

    /// `@autoclosure` defers the interpolation, so a dropped debug line never builds its message.
    static func error(_ tag: String, _ message: @autoclosure () -> String) { emit(.error, tag, message) }
    static func warn(_ tag: String, _ message: @autoclosure () -> String) { emit(.warn, tag, message) }
    static func info(_ tag: String, _ message: @autoclosure () -> String) { emit(.info, tag, message) }
    static func debug(_ tag: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        emit(.debug, tag, message)
        #endif
    }

    // Convenience overloads for the typed tags (the common case).
    static func error(_ tag: LogTag, _ message: @autoclosure () -> String) { error(tag.rawValue, message()) }
    static func warn(_ tag: LogTag, _ message: @autoclosure () -> String) { warn(tag.rawValue, message()) }
    static func info(_ tag: LogTag, _ message: @autoclosure () -> String) { info(tag.rawValue, message()) }
    static func debug(_ tag: LogTag, _ message: @autoclosure () -> String) {
        #if DEBUG
        emit(.debug, tag.rawValue, message)
        #endif
    }

    private static func emit(_ level: Level, _ tag: String, _ message: () -> String) {
        let redacted = LogRedaction.redactLogMessage(message())
        logger(for: tag).log(level: level.osType, "[\(tag, privacy: .public)] \(redacted, privacy: .public)")
    }

    private static func logger(for tag: String) -> Logger {
        loggerLock.lock()
        defer { loggerLock.unlock() }
        if let existing = loggers[tag] { return existing }
        let logger = Logger(subsystem: "OpenUsage", category: tag)
        loggers[tag] = logger
        return logger
    }
}
