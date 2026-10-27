import Foundation

/// The token pair an OAuth refresh returns, for the auth store to persist under the official lock.
struct KimiRefreshedTokens: Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var scope: String?
    var tokenType: String?
}

enum KimiUsageError: Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return ProviderUsageErrorText.connectionFailed
        case .invalidResponse:
            return ProviderUsageErrorText.invalidResponse
        case .requestFailed(let status):
            return ProviderUsageErrorText.requestFailed(statusCode: status)
        }
    }
}

/// Calls Kimi's coding-usage endpoint and the Kimi OAuth refresh endpoint. Both are undocumented
/// internal APIs used by the Kimi Code CLI itself (`/usage` shows the same numbers); the response
/// shapes are the ones QuotaWidget documented and fixture-tested.
struct KimiUsageClient: Sendable {
    static let usageURL = URL(string: "https://api.kimi.com/coding/v1/usages")!
    static let refreshURL = URL(string: "https://auth.kimi.com/api/oauth/token")!
    /// The public client id the official Kimi Code CLI registers with; a refresh without it is
    /// rejected, so it ships here exactly as QuotaWidget captured it.
    static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"

    var http: any HTTPClient

    init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func fetchUsage(accessToken: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(
            method: "GET",
            url: Self.usageURL,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Accept": "application/json",
            ],
            timeout: 20
        ))
    }

    /// Rotates the OAuth token pair. Throws `KimiAuthError.refreshRejected` when the refresh token
    /// no longer grants (HTTP 401/403 or `invalid_grant`), so the provider can say "log in again".
    func refreshTokens(refreshToken: String) async throws -> KimiRefreshedTokens {
        let body = [
            "client_id=\(Self.clientID)",
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
        ].joined(separator: "&")
        let response: HTTPResponse
        do {
            response = try await http.send(HTTPRequest(
                method: "POST",
                url: Self.refreshURL,
                headers: [
                    "Accept": "application/json",
                    "Content-Type": "application/x-www-form-urlencoded",
                ],
                body: Data(body.utf8),
                timeout: 20
            ))
        } catch {
            throw KimiUsageError.connectionFailed
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw KimiAuthError.refreshRejected
            }
            throw KimiUsageError.requestFailed(response.statusCode)
        }
        guard let object = ProviderParse.jsonObject(response.body),
              let accessToken = object["access_token"] as? String, !accessToken.isEmpty,
              let rotatedRefresh = object["refresh_token"] as? String, !rotatedRefresh.isEmpty
        else {
            throw KimiUsageError.invalidResponse
        }
        return KimiRefreshedTokens(
            accessToken: accessToken,
            refreshToken: rotatedRefresh,
            expiresIn: Int(ProviderParse.number(object["expires_in"]) ?? 0),
            scope: object["scope"] as? String,
            tokenType: object["token_type"] as? String
        )
    }
}
