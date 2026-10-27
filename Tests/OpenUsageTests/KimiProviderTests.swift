import XCTest
@testable import OpenUsage

private let kimiUsageJSON = #"""
{
  "usage": {"limit": 1000, "remaining": 920, "resetTime": {"seconds": "1781600000"}},
  "limits": [
    {"window": {"duration": 300, "timeUnit": "MINUTE"},
     "detail": {"limit": 100, "used": 34, "reset_at": 1781190000}}
  ]
}
"""#

private let kimiTokenJSON = #"{"access_token":"rotated","refresh_token":"rt2","expires_in":3600}"#

/// End-to-end provider refresh against a stubbed HTTP layer: credential loading, the expired-token
/// refresh path, the 401 retry-after-rotation path, and error classification.
@MainActor
final class KimiProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testNotLoggedInSurfacesTypedError() async {
        let provider = makeProvider(files: [:])
        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .notLoggedIn)
        guard case .badge("Error", let text, _, _)? = snapshot.line(label: "Error") else {
            return XCTFail("expected an error badge")
        }
        XCTAssertTrue(text.contains("/login"), text)
    }

    func testMapsUsageToSessionAndWeekly() async throws {
        let http = ScriptedHTTPClient(usage: [.success(.json(kimiUsageJSON))])
        let provider = makeProvider(files: credentialFiles(expiresAt: 1_790_000_000), http: http)
        let snapshot = await provider.refresh()

        XCTAssertNil(snapshot.errorCategory)
        guard case .progress(_, 34, 100, .percent, _, _, _)? = snapshot.line(label: "Session") else {
            return XCTFail("expected a 34% Session meter, got \(String(describing: snapshot.line(label: "Session")))")
        }
        guard case .progress(_, 8, 100, .percent, let resetsAt?, _, _)? = snapshot.line(label: "Weekly") else {
            return XCTFail("expected an 8% Weekly meter with a reset, got \(String(describing: snapshot.line(label: "Weekly")))")
        }
        XCTAssertEqual(resetsAt, Date(timeIntervalSince1970: 1_781_600_000))
        XCTAssertEqual(http.requests.map { $0.url }, [KimiUsageClient.usageURL], "a live token makes no refresh call")
    }

    func testRefreshesExpiredTokenBeforeFetchingUsage() async throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let http = ScriptedHTTPClient(
            usage: [.success(.json(kimiUsageJSON))],
            token: [.success(.json(kimiTokenJSON))]
        )
        let provider = makeProvider(home: home, expiresAt: 1_700_000_000, http: http) // dead token
        let snapshot = await provider.refresh()

        XCTAssertNil(snapshot.errorCategory)
        XCTAssertNotNil(snapshot.line(label: "Session"))
        XCTAssertEqual(http.requests.map { $0.url }, [KimiUsageClient.refreshURL, KimiUsageClient.usageURL])
        XCTAssertEqual(http.requests[1].headers["Authorization"], "Bearer rotated")
        // The rotation is persisted under the official lock for the CLI to reuse.
        let persisted = String(decoding: try Data(contentsOf: credentialURL(home)), as: UTF8.self)
        XCTAssertEqual(persistedObject(persisted)?["access_token"] as? String, "rotated")
    }

    func testUnauthorizedRefreshesOnceAndRetries() async throws {
        let http = ScriptedHTTPClient(
            usage: [
                .success(.init(statusCode: 401, headers: [:], body: Data())),
                .success(.json(kimiUsageJSON)),
            ],
            token: [.success(.json(kimiTokenJSON))]
        )
        let provider = makeProvider(files: credentialFiles(expiresAt: 1_790_000_000), http: http) // live token
        let snapshot = await provider.refresh()

        XCTAssertNil(snapshot.errorCategory)
        XCTAssertNotNil(snapshot.line(label: "Session"))
        XCTAssertEqual(
            http.requests.map { $0.url },
            [KimiUsageClient.usageURL, KimiUsageClient.refreshURL, KimiUsageClient.usageURL]
        )
        XCTAssertEqual(http.requests[2].headers["Authorization"], "Bearer rotated")
    }

    func testUnauthorizedAfterRotationFailsAsSessionExpired() async {
        let http = ScriptedHTTPClient(
            usage: [
                .success(.init(statusCode: 401, headers: [:], body: Data())),
                .success(.json(kimiUsageJSON)),
            ],
            token: [.failure(KimiAuthError.refreshRejected)]
        )
        let provider = makeProvider(files: credentialFiles(expiresAt: 1_790_000_000), http: http)
        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .authExpired)
    }

    func testConnectionFailureIsANetworkError() async {
        let http = ScriptedHTTPClient(usage: [.failure(KimiUsageError.connectionFailed)])
        let provider = makeProvider(files: credentialFiles(expiresAt: 1_790_000_000), http: http)
        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .network)
    }

    func testHTTPErrorClassifiesByStatus() async {
        let http = ScriptedHTTPClient(usage: [.success(.init(statusCode: 429, headers: [:], body: Data()))])
        let provider = makeProvider(files: credentialFiles(expiresAt: 1_790_000_000), http: http)
        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .rateLimited)
    }

    func testMalformedUsageBodyIsADecodingError() async {
        let http = ScriptedHTTPClient(usage: [.success(.json("not json"))])
        let provider = makeProvider(files: credentialFiles(expiresAt: 1_790_000_000), http: http)
        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .decoding)
    }

    // MARK: - Helpers

    private func tempHome() -> String {
        NSTemporaryDirectory() + "kimi-provider-tests-\(UUID().uuidString)"
    }

    private func credentialURL(_ home: String) -> URL {
        URL(fileURLWithPath: "\(home)/credentials/kimi-code.json")
    }

    private func persistedObject(_ text: String) -> [String: Any]? {
        KimiAuthStore.parseJSONObject(text)
    }

    /// FakeFiles-based credentials under an absolute fake home; `expiresAt` is epoch seconds.
    private func credentialFiles(expiresAt: TimeInterval) -> [String: String] {
        [
            "/tmp/kimi-provider-test/credentials/kimi-code.json": #"""
            {"access_token":"token","refresh_token":"rt","expires_at":\#(Int(expiresAt))}
            """#,
        ]
    }

    private func makeProvider(
        files: [String: String],
        http: ScriptedHTTPClient = ScriptedHTTPClient(usage: [])
    ) -> KimiProvider {
        let fixedNow = self.now
        return KimiProvider(
            authStore: KimiAuthStore(
                environment: FakeEnvironment(["KIMI_CODE_HOME": "/tmp/kimi-provider-test"]),
                files: FakeFiles(files),
                now: { fixedNow }
            ),
            usageClient: KimiUsageClient(http: http),
            now: { fixedNow }
        )
    }

    /// Real-filesystem variant so the refresh persistence can be asserted on disk.
    private func makeProvider(home: String, expiresAt: TimeInterval, http: ScriptedHTTPClient) -> KimiProvider {
        let fixedNow = self.now
        try! FileManager.default.createDirectory(
            at: credentialURL(home).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try! Data(#"{"access_token":"token","refresh_token":"rt","expires_at":\#(Int(expiresAt))}"#.utf8)
            .write(to: credentialURL(home))
        return KimiProvider(
            authStore: KimiAuthStore(
                environment: FakeEnvironment(["KIMI_CODE_HOME": home]),
                now: { fixedNow }
            ),
            usageClient: KimiUsageClient(http: http),
            now: { fixedNow }
        )
    }
}

private extension HTTPResponse {
    static func json(_ body: String) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
    }
}

/// URL-scripted stub: each URL gets its own FIFO queue so a refresh POST and a usage GET can
/// return different canned bodies within one test.
final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    private var queues: [URL: [Result<HTTPResponse, Error>]]
    private(set) var requests: [HTTPRequest] = []

    init(usage: [Result<HTTPResponse, Error>], token: [Result<HTTPResponse, Error>] = []) {
        self.queues = [KimiUsageClient.usageURL: usage, KimiUsageClient.refreshURL: token]
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard let queue = queues[request.url], !queue.isEmpty else {
            throw KimiUsageError.connectionFailed
        }
        queues[request.url] = Array(queue.dropFirst())
        return try queue[0].get()
    }
}
