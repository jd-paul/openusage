import XCTest
@testable import OpenUsage

/// Credential-file reading, expiry, and the official-lock refresh persistence for the Kimi provider.
/// Load tests run against `FakeFiles` with absolute env paths; the refresh flow exercises the real
/// filesystem (POSIX lock + atomic write are deliberately not abstracted) in a unique temp dir.
final class KimiAuthStoreTests: XCTestCase {
    private let currentPath = "/tmp/kimi-test-current/credentials/kimi-code.json"
    private let legacyPath = "/tmp/kimi-test-legacy/credentials/kimi-code.json"

    func testPrefersCurrentStoreAndFallsBackToLegacy() {
        let env = FakeEnvironment([
            "KIMI_CODE_HOME": "/tmp/kimi-test-current",
            "KIMI_SHARE_DIR": "/tmp/kimi-test-legacy",
        ])
        let current = #"{"access_token":"current"}"#
        let legacy = #"{"access_token":"legacy"}"#

        let both = KimiAuthStore(environment: env, files: FakeFiles([currentPath: current, legacyPath: legacy]))
        XCTAssertEqual(both.load()?.document.accessToken, "current")

        let onlyLegacy = KimiAuthStore(environment: env, files: FakeFiles([legacyPath: legacy]))
        XCTAssertEqual(onlyLegacy.load()?.document.accessToken, "legacy")

        let none = KimiAuthStore(environment: env, files: FakeFiles())
        XCTAssertNil(none.load())
        XCTAssertFalse(none.hasUsableCredentials())
    }

    func testSkipsMalformedAndTokenlessFiles() {
        let env = FakeEnvironment(["KIMI_CODE_HOME": "/tmp/kimi-test-current"])
        let files = FakeFiles([
            currentPath: #"{"refresh_token":"no-access-token-here"}"#,
        ])
        let store = KimiAuthStore(environment: env, files: files)
        XCTAssertNil(store.load())
        XCTAssertFalse(store.hasUsableCredentials())
    }

    func testExpiryAndRefreshBuffer() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func file(expiresAt: TimeInterval) -> KimiCredentialFile {
            KimiCredentialFile(
                document: KimiCredentialDocument(object: ["access_token": "a", "expires_at": expiresAt]),
                path: currentPath
            )
        }
        let store = KimiAuthStore(environment: FakeEnvironment(), files: FakeFiles(), now: { now })

        XCTAssertTrue(store.isExpired(file(expiresAt: 999_999)))
        XCTAssertFalse(store.isExpired(file(expiresAt: 1_000_001)))
        // Unknown/zero expiry is treated as live (the usage call is the authority).
        XCTAssertFalse(store.isExpired(file(expiresAt: 0)))
        // Inside the 5-minute buffer counts as needing a refresh, even though not yet expired.
        XCTAssertTrue(store.needsRefresh(file(expiresAt: 1_000_000 + 120)))
        XCTAssertFalse(store.needsRefresh(file(expiresAt: 1_000_000 + 3_600_000)))
    }

    func testRotatedDetectsTokenChangesOnly() {
        func doc(_ access: String, _ refresh: String, _ expiresAt: Double) -> KimiCredentialDocument {
            KimiCredentialDocument(object: [
                "access_token": access, "refresh_token": refresh, "expires_at": expiresAt,
            ])
        }
        let base = doc("a", "r", 100)
        XCTAssertFalse(base.rotated(relativeTo: base))
        XCTAssertTrue(base.rotated(relativeTo: doc("b", "r", 100)))
        XCTAssertTrue(base.rotated(relativeTo: doc("a", "r2", 100)))
        XCTAssertTrue(base.rotated(relativeTo: doc("a", "r", 200)))
    }

    func testRefreshPersistsRotatedTokensAndPreservesUnknownFields() async throws {
        let home = uniqueTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let path = "\(home)/credentials/kimi-code.json"
        let initialJSON = #"{"access_token":"old","refresh_token":"rt","expires_at":1,"account_label":"keep-me"}"#
        try write(initialJSON, to: path)

        let store = KimiAuthStore(
            environment: FakeEnvironment(["KIMI_CODE_HOME": home]),
            now: { Date(timeIntervalSince1970: 2_000_000) }
        )
        let file = try XCTUnwrap(store.load())

        let document = try await store.refreshCredentials(file, force: false) { refreshToken in
            XCTAssertEqual(refreshToken, "rt")
            return KimiRefreshedTokens(
                accessToken: "new", refreshToken: "rt2", expiresIn: 3600,
                scope: "user:profile", tokenType: "Bearer"
            )
        }

        XCTAssertEqual(document.accessToken, "new")
        let persisted = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        let persistedObject = try XCTUnwrap(KimiAuthStore.parseJSONObject(persisted))
        XCTAssertEqual(persistedObject["access_token"] as? String, "new")
        XCTAssertEqual(persistedObject["refresh_token"] as? String, "rt2")
        XCTAssertEqual(persistedObject["account_label"] as? String, "keep-me")
        XCTAssertEqual(persistedObject["expires_in"] as? Int, 3600)
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testRefreshSkipsNetworkWhenFileAlreadyRotated() async throws {
        let home = uniqueTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let path = "\(home)/credentials/kimi-code.json"
        try write(#"{"access_token":"initial","refresh_token":"rt","expires_at":1}"#, to: path)

        let store = KimiAuthStore(
            environment: FakeEnvironment(["KIMI_CODE_HOME": home]),
            now: { Date(timeIntervalSince1970: 2_000_000) }
        )
        // Another process rotated the file between our load and the lock acquisition.
        try write(#"{"access_token":"rotated-by-cli","refresh_token":"rt","expires_at":3000000}"#, to: path)

        let file = KimiCredentialFile(
            document: KimiCredentialDocument(object: ["access_token": "initial", "refresh_token": "rt", "expires_at": 1]),
            path: path
        )
        let document = try await store.refreshCredentials(file, force: false) { _ in
            throw KimiAuthError.refreshRejected // must never be called
        }
        XCTAssertEqual(document.accessToken, "rotated-by-cli")
    }

    func testRefreshThrowsRejectionWithoutPersisting() async throws {
        let home = uniqueTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let path = "\(home)/credentials/kimi-code.json"
        try write(#"{"access_token":"old","refresh_token":"rt","expires_at":1}"#, to: path)

        let store = KimiAuthStore(
            environment: FakeEnvironment(["KIMI_CODE_HOME": home]),
            now: { Date(timeIntervalSince1970: 2_000_000) }
        )
        let file = try XCTUnwrap(store.load())

        await XCTAssertThrowsErrorAsync(
            try await store.refreshCredentials(file, force: false) { _ in
                throw KimiAuthError.refreshRejected
            }
        ) { error in
            XCTAssertEqual(error as? KimiAuthError, .refreshRejected)
        }
        let persisted = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        XCTAssertEqual(persistedObject(persisted)?["access_token"] as? String, "old")
    }

    func testUnexpiredDocumentSkipsRefresh() async throws {
        let home = uniqueTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let path = "\(home)/credentials/kimi-code.json"
        try write(#"{"access_token":"live","refresh_token":"rt","expires_at":3000000}"#, to: path)

        let store = KimiAuthStore(
            environment: FakeEnvironment(["KIMI_CODE_HOME": home]),
            now: { Date(timeIntervalSince1970: 2_000_000) }
        )
        let file = try XCTUnwrap(store.load())
        let document = try await store.refreshCredentials(file, force: false) { _ in
            throw KimiAuthError.refreshRejected // must never be called
        }
        XCTAssertEqual(document.accessToken, "live")
    }

    // MARK: - Helpers

    private func uniqueTempHome() -> String {
        NSTemporaryDirectory() + "kimi-auth-tests-\(UUID().uuidString)"
    }

    private func write(_ text: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    private func persistedObject(_ text: String) -> [String: Any]? {
        KimiAuthStore.parseJSONObject(text)
    }

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message() == "" ? "Expected an error to be thrown" : message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
