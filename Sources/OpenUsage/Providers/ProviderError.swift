import Foundation

/// The failures an account refresh surfaces on its dashboard card. Every case maps to one message the
/// card shows; no case carries a credential or a response body.
enum ProviderError: Error, LocalizedError, Equatable {
    /// The saved sign-in no longer works (the provider answered 401/403, refused the token refresh, or
    /// asked for a sign-out), so only adding the account again fixes it.
    case signInExpired(ProviderKind)
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)
    /// The provider answered, but has nothing to meter for this account; the message says why.
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .signInExpired(let kind): "\(kind.displayName) sign-in expired. Add the account again."
        case .connectionFailed: "Connection failed. Check your internet connection and try again."
        case .invalidResponse: "The provider returned an invalid response."
        case .requestFailed(let status): "The provider request failed (HTTP \(status))."
        case .unavailable(let message): message
        }
    }
}
