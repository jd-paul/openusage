import Foundation

struct ClaudeOAuthConfig: Hashable, Sendable {
    var usageURL: URL
    var refreshURL: URL
    var clientID: String
}

struct ClaudeOAuth: Hashable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double?
    var subscriptionType: String?
    var rateLimitTier: String?
}

enum ClaudeAuthError: Error, LocalizedError, Equatable {
    case tokenExpired

    var errorDescription: String? {
        "Claude sign-in expired. Add the account again."
    }
}

enum CodexAuthError: Error, LocalizedError, Equatable {
    case sessionExpired
    case tokenConflict
    case tokenRevoked
    case tokenExpired

    var errorDescription: String? {
        "Codex sign-in expired. Add the account again."
    }
}

enum CursorAuthError: Error, LocalizedError, Equatable {
    case sessionExpired
    case tokenExpired

    var errorDescription: String? {
        "Cursor sign-in expired. Add the account again."
    }
}

enum GrokAuthError: Error, LocalizedError, Equatable {
    case expired

    var errorDescription: String? {
        "Grok sign-in expired. Add the account again."
    }
}

enum OpenCodeUsageError: Error, LocalizedError, Equatable {
    case invalidResponse

    var errorDescription: String? {
        ProviderUsageErrorText.invalidResponse
    }
}
