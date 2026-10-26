import Foundation

/// Failures for an Antigravity account's token refresh and quota calls.
enum AntigravityError: Error, LocalizedError, Equatable {
    /// Cloud Code rejected the token (401/403), or Google refused the refresh token.
    case authExpired
    /// Every Cloud Code host was unreachable or answered with a non-auth error, or the token refresh
    /// failed transiently.
    case unavailable
    /// A 2xx body that isn't a quota summary.
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authExpired:
            return "Antigravity sign-in expired. Add the account again."
        case .unavailable:
            return "Antigravity usage is temporarily unavailable. Try again shortly."
        case .invalidResponse:
            return ProviderUsageErrorText.invalidResponse
        }
    }
}
