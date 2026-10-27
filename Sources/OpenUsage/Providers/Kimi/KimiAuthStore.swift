import Foundation

enum KimiAuthError: Error, LocalizedError, Equatable {
    case notLoggedIn
    case sessionExpired
    case refreshRejected

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Kimi not logged in. Run `kimi` and /login to authenticate."
        case .sessionExpired:
            return "Kimi session expired. Run `kimi` and /login again."
        case .refreshRejected:
            return "Kimi login was rejected. Run `kimi` and /login again."
        }
    }
}

/// One parsed Kimi Code credential file. The parsed JSON object is preserved wholesale so a rotated
/// token can be written back without dropping fields Kimi Code added that this app doesn't read.
struct KimiCredentialDocument: @unchecked Sendable {
    var object: [String: Any]

    var accessToken: String? { Self.trimmed(object["access_token"]) }
    var refreshToken: String? { Self.trimmed(object["refresh_token"]) }

    /// Epoch seconds; `0`/absent means unknown, treated as unexpired (the usage call itself is the
    /// authority, and a rejected token surfaces as a typed auth error).
    var expiresAt: TimeInterval { Self.number(object["expires_at"]) ?? 0 }

    func isExpired(now: TimeInterval) -> Bool {
        let value = expiresAt
        return value != 0 && value <= now
    }

    /// True when the token material differs from `other` in any way that matters for rotation —
    /// a token written by another process while we held the refresh lock.
    func rotated(relativeTo other: KimiCredentialDocument) -> Bool {
        accessToken != other.accessToken
            || refreshToken != other.refreshToken
            || expiresAt != other.expiresAt
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> TimeInterval? {
        ProviderParse.number(value)
    }
}

struct KimiCredentialFile: Sendable {
    var document: KimiCredentialDocument
    var path: String
}

/// Reads the Kimi Code CLI's OAuth credentials from the machine and persists token rotations
/// exactly the way the official CLI does: under the shared `oauth/kimi-code.lock` directory lock,
/// re-reading the file after locking, then writing atomically with 0600 permissions. The legacy
/// `~/.kimi` store is read (and refreshed in place) when the current store is absent.
struct KimiAuthStore: Sendable {
    private static let currentHomeVariable = "KIMI_CODE_HOME"
    private static let legacyHomeVariable = "KIMI_SHARE_DIR"
    private static let currentDefaultHome = "~/.kimi-code"
    private static let legacyDefaultHome = "~/.kimi"
    private static let credentialFile = "credentials/kimi-code.json"
    private static let refreshBuffer: TimeInterval = 5 * 60

    var environment: EnvironmentReading
    var files: TextFileAccessing
    var now: @Sendable () -> Date

    init(
        environment: EnvironmentReading = ProcessEnvironmentReader(),
        files: TextFileAccessing = LocalTextFileAccessor(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.environment = environment
        self.files = files
        self.now = now
    }

    /// Current-store path first, then the legacy store — the same resolution `refresh()` reads.
    /// Order matters: a `Set` would shuffle which store wins, so dedupe manually.
    func credentialPaths() -> [String] {
        let current = env(Self.currentHomeVariable) ?? Self.currentDefaultHome
        let legacy = env(Self.legacyHomeVariable) ?? Self.legacyDefaultHome
        var seen = Set<String>()
        return [
            "\(current)/\(Self.credentialFile)",
            "\(legacy)/\(Self.credentialFile)",
        ].filter { seen.insert($0).inserted }
    }

    func load() -> KimiCredentialFile? {
        for path in credentialPaths() {
            guard let text = try? files.readTextIfPresent(expanded(path)),
                  let object = KimiAuthStore.parseJSONObject(text),
                  KimiCredentialDocument(object: object).accessToken != nil
            else { continue }
            return KimiCredentialFile(document: KimiCredentialDocument(object: object), path: path)
        }
        return nil
    }

    /// The probe behind first-launch detection: cheap, local-only, and mirroring `refresh()` —
    /// a credential file that parses and carries an access token counts as a login.
    func hasUsableCredentials() -> Bool {
        load() != nil
    }

    func needsRefresh(_ file: KimiCredentialFile) -> Bool {
        let value = file.document.expiresAt
        guard value != 0 else { return false }
        return value - now().timeIntervalSince1970 <= Self.refreshBuffer
    }

    func isExpired(_ file: KimiCredentialFile) -> Bool {
        file.document.isExpired(now: now().timeIntervalSince1970)
    }

    /// Rotates the token under the official lock and persists the result. When the file changed
    /// between `initial` and the post-lock re-read (another process rotated it first), the newer
    /// document is returned without a network call. `force` skips the not-yet-expired check.
    /// `refresh` performs the HTTP call so this store never owns networking.
    func refreshCredentials(
        _ initial: KimiCredentialFile,
        force: Bool,
        refresh: @escaping @Sendable (String) async throws -> KimiRefreshedTokens
    ) async throws -> KimiCredentialDocument {
        try await withRefreshLock(near: initial.path) {
            let stored = self.read(path: initial.path)
            let active = stored ?? initial.document
            if let stored, stored.rotated(relativeTo: initial.document), stored.accessToken != nil {
                return stored
            }
            if !force && !active.isExpired(now: self.now().timeIntervalSince1970) {
                return active
            }
            guard let refreshToken = active.refreshToken else {
                throw KimiAuthError.refreshRejected
            }
            let refreshed = try await refresh(refreshToken)
            var object = active.object
            object["access_token"] = refreshed.accessToken
            object["refresh_token"] = refreshed.refreshToken
            object["expires_in"] = refreshed.expiresIn
            object["expires_at"] = Int(self.now().timeIntervalSince1970) + refreshed.expiresIn
            if let scope = refreshed.scope { object["scope"] = scope }
            if let tokenType = refreshed.tokenType { object["token_type"] = tokenType }
            let document = KimiCredentialDocument(object: object)
            try self.writeAtomically(document, to: initial.path)
            return document
        }
    }

    static func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Official lock protocol

    /// Kimi Code's cross-process refresh exclusion: a `kimi-code.lock` directory next to `oauth/`,
    /// created with mkdir's atomic exists semantics, heartbeated while held, broken after 5s stale.
    /// Mirrors the protocol QuotaWidget documented against the official CLI.
    private func withRefreshLock<T>(
        near credentialPath: String,
        operation: () async throws -> T
    ) async throws -> T {
        let lockPath = lockPath(near: credentialPath)
        try await acquireLock(path: lockPath)
        let heartbeat = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        heartbeat.setEventHandler {
            var now = timeval()
            gettimeofday(&now, nil)
            var times = [timespec(tv_sec: now.tv_sec, tv_nsec: Int(now.tv_usec) * 1000), timespec(tv_sec: now.tv_sec, tv_nsec: Int(now.tv_usec) * 1000)]
            _ = utimensat(AT_FDCWD, lockPath, &times, 0)
        }
        heartbeat.schedule(deadline: .now() + 2, repeating: 2)
        heartbeat.resume()
        defer {
            heartbeat.cancel()
            _ = rmdir(lockPath)
        }
        return try await operation()
    }

    private func acquireLock(path: String) async throws {
        // POSIX mkdir creates only the leaf — make the parent first so the lock works even before
        // the Kimi Code CLI has ever created its oauth/ directory.
        let parent = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        let deadline = now().addingTimeInterval(60)
        while true {
            if mkdir(path, 0o700) == 0 { return }
            if errno != EEXIST {
                throw KimiAuthError.refreshRejected
            }
            if staleness(of: path) > 5, rmdir(path) == 0 {
                continue
            }
            if now() >= deadline {
                throw KimiAuthError.refreshRejected
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Seconds since the lock directory was last touched; 0 when it can't be read.
    private func staleness(of path: String) -> TimeInterval {
        var statBuffer = stat()
        guard stat(path, &statBuffer) == 0 else { return 0 }
        return now().timeIntervalSince1970 - statBuffer.st_mtimespec.timeIntervalSince1970
    }

    private func lockPath(near credentialPath: String) -> String {
        let home = expanded(credentialPath).components(separatedBy: "/")
            .dropLast(2).joined(separator: "/")
        return "\(home)/oauth/kimi-code.lock"
    }

    // MARK: - Atomic persistence

    private func read(path: String) -> KimiCredentialDocument? {
        guard let text = try? files.readTextIfPresent(expanded(path)),
              let object = Self.parseJSONObject(text)
        else { return nil }
        return KimiCredentialDocument(object: object)
    }

    private func writeAtomically(_ document: KimiCredentialDocument, to path: String) throws {
        let path = expanded(path)
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        if let parent = (directory as NSString).deletingLastPathComponent.nilIfEmpty {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent)
        }
        let temporary = directory + "/\(UUID().uuidString).tmp"
        let data = try JSONSerialization.data(withJSONObject: document.object, options: [.prettyPrinted, .sortedKeys])
        FileManager.default.createFile(atPath: temporary, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: temporary))
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.close()
        // POSIX rename replaces atomically; FileManager.moveItem refuses an existing destination.
        if rename(temporary, path) != 0 {
            try FileManager.default.removeItem(atPath: temporary)
            throw KimiAuthError.refreshRejected
        }
    }

    private func env(_ name: String) -> String? {
        environment.value(for: name)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func expanded(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

private extension timespec {
    var timeIntervalSince1970: TimeInterval { TimeInterval(tv_sec) + TimeInterval(tv_nsec) / 1e9 }
}
