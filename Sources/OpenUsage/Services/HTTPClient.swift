import Foundation

struct HTTPRequest: Sendable {
    var method: String
    var url: URL
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = 15
}

struct HTTPResponse: Sendable {
    var statusCode: Int
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

struct URLSessionHTTPClient: HTTPClient {
    /// When true, requests use a loopback session that accepts a self-signed TLS cert for `127.0.0.1`
    /// only (see `LoopbackTLSDelegate`). The local language server serves HTTPS with a self-signed cert
    /// on a random localhost port; nothing else needs this. Off by default so remote calls keep full
    /// certificate validation.
    var allowsInsecureLoopback: Bool = false

    private static let session = URLSession(configuration: .default)

    /// Loopback-only session: ephemeral (no shared cookie/cache state), no proxy (localhost), and a
    /// delegate that trusts a self-signed cert exclusively for `127.0.0.1`. Built once.
    private static let loopbackSession: URLSession = {
        URLSession(configuration: .ephemeral, delegate: LoopbackTLSDelegate(), delegateQueue: nil)
    }()

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let session = allowsInsecureLoopback ? Self.loopbackSession : Self.session
        let start = ContinuousClock.now
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        let result = HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
        AppLog.debug(.http, Self.diagnostic(for: request, response: result, duration: ContinuousClock.now - start))
        return result
    }

    /// The one line the transport logs per exchange: method, host and path, status, and duration.
    /// It never reads the query, the headers, or either body, so a credential in any of them (an
    /// `Authorization` header, Cursor's PKCE verifier in the poll query, a token echoed in an error
    /// body) cannot reach the log.
    static func diagnostic(for request: HTTPRequest, response: HTTPResponse, duration: Duration) -> String {
        let milliseconds = Int((duration / .milliseconds(1)).rounded())
        let endpoint = (request.url.host() ?? "") + request.url.path()
        return "\(request.method) \(endpoint) -> \(response.statusCode) (\(milliseconds) ms)"
    }
}

enum HTTPClientError: Error, LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Invalid HTTP response."
    }
}

/// Accepts a self-signed server cert ONLY for loopback (`127.0.0.1`). Every other host — and every
/// non-server-trust challenge — falls through to default validation, so this never weakens trust for a
/// real remote endpoint. Holds no mutable state, so it is safe to share across the loopback session.
private final class LoopbackTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == "127.0.0.1",
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
