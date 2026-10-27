import Foundation

enum ProviderAuthRetry {
    static func isAuthFailure(_ response: HTTPResponse) -> Bool {
        response.statusCode == 401 || response.statusCode == 403
    }

    /// Triages a non-2xx: 401/403 means the sign-in expired, 429 a rate limit, anything else a request
    /// failure that carries its status.
    static func requireSuccess(_ response: HTTPResponse, kind: ProviderKind) throws {
        if isAuthFailure(response) { throw ProviderError.signInExpired(kind) }
        guard (200..<300).contains(response.statusCode) else { throw ProviderError.failed(response) }
    }

    /// Sends a request. On a 401/403 it refreshes the token once and retries with the new one. The
    /// caller triages the final response with `requireSuccess`, so a second 401/403 reads as expired.
    @MainActor
    static func fetch(
        token: String,
        attempt: (String) async throws -> HTTPResponse,
        refreshAccessToken: () async throws -> String
    ) async throws -> HTTPResponse {
        let response = try await attempt(token)
        guard isAuthFailure(response) else { return response }
        return try await attempt(try await refreshAccessToken())
    }
}
