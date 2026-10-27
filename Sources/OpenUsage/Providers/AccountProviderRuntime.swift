import Foundation

@MainActor
final class AccountProviderRuntime: ProviderRuntime {
    private(set) var account: Account
    private(set) var provider: Provider
    let vault: any CredentialVault
    let http: any HTTPClient
    let now: () -> Date
    /// Claude's plan from `/api/oauth/profile`, looked up once per access token. The in-app login never
    /// receives a plan, so the profile is the only source of it.
    private var claudePlan: (accessToken: String, plan: String)?
    /// Claude's reset-grants state, carried across refreshes (see `AccountProviderRuntime+ClaudeResets`).
    var claudeResetGrants = ClaudeResetGrantsState()
    /// The Codex credit each claim's idempotency key was matched to (see `AccountProviderRuntime+CodexResets`).
    var codexMatchedCreditIDs: [String: String] = [:]

    init(
        account: Account,
        vault: any CredentialVault,
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.account = account
        self.vault = vault
        self.http = http
        self.now = now
        provider = Self.provider(for: account)
    }

    /// Picks up a rename without replacing the runtime.
    func update(_ account: Account) {
        self.account = account
        provider = Self.provider(for: account)
    }

    static func provider(for account: Account) -> Provider {
        Provider(
            id: account.cardID,
            displayName: account.kind.displayName,
            icon: account.kind.rawValue,
            accountLabel: account.label,
            links: account.kind.links
        )
    }

    /// The resets popover's claim seam for this account, or `nil` for providers without reset claims.
    /// Claude always spends the grant Anthropic names next, so the picked node's expiry only matters to
    /// Codex.
    func resetClaimService(
        refreshAccount: @escaping @MainActor () async -> WidgetDataStore.RefreshOutcome
    ) -> ResetClaimService? {
        switch account.kind {
        case .claude:
            let status = claudeResetGrants.check?.status
            return ResetClaimService(
                accountID: account.cardID,
                isClaimable: status?.claimableGrantID != nil,
                confirmDetail: status?.confirmDetail,
                claimReset: { [self] _, redeemRequestID in await claimClaudeResetGrant(redeemRequestID: redeemRequestID) },
                refreshAccount: refreshAccount
            )
        case .codex:
            return ResetClaimService(
                accountID: account.cardID,
                isClaimable: true,
                confirmDetail: nil,
                claimReset: { [self] expiry, redeemRequestID in
                    await claimCodexResetCredit(expiringAt: expiry, redeemRequestID: redeemRequestID)
                },
                refreshAccount: refreshAccount
            )
        case .cursor, .antigravity, .copilot, .grok, .ollama, .opencodeGo, .openrouter, .zai:
            return nil
        }
    }

    func refresh() async -> ProviderSnapshot {
        do {
            let result = try await refresh(try await loadCredential())
            return ProviderSnapshot.make(provider: provider, plan: result.plan, lines: result.lines, refreshedAt: Date())
        } catch {
            return ProviderSnapshot.error(provider: provider, error: error)
        }
    }

    /// The account's own credential from the vault; the only credential a refresh or claim ever uses.
    func loadCredential() async throws -> AccountCredential {
        guard let credential = try await loadOffMainActor({ [vault, account] in try vault.load(account.id) }) else {
            throw LoginError.cancelled
        }
        return credential
    }

    private func refresh(_ credential: AccountCredential) async throws -> (plan: String?, lines: [MetricLine]) {
        switch account.kind {
        case .claude: try await refreshClaude(credential)
        case .codex: try await refreshCodex(credential)
        case .cursor: try await refreshCursor(credential)
        case .antigravity: try await refreshAntigravity(credential)
        case .copilot: try await refreshCopilot(credential)
        case .grok: try await refreshGrok(credential)
        case .ollama: try await refreshOllama(credential)
        case .opencodeGo: try await refreshOpenCode(credential)
        case .openrouter: try await refreshOpenRouter(credential)
        case .zai: try await refreshZAI(credential)
        }
    }

    static let claudeConfig = ClaudeOAuthConfig(
        usageURL: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        refreshURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
        clientID: ClaudeLogin.clientID
    )

    /// The account's Claude tokens, refreshed and saved back to the vault first when they expire within
    /// `OAuthTokens.refreshMargin`.
    func claudeTokens(_ credential: AccountCredential) async throws -> OAuthTokens {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        if tokens.needsRefresh(at: now()), let refreshToken = tokens.refreshToken {
            let response = try await ClaudeUsageClient(httpClient: http).refreshToken(refreshToken, config: Self.claudeConfig)
            guard (200..<300).contains(response.statusCode) else { throw ProviderError.failed(response) }
            let refreshed = try JSONDecoder().decode(ClaudeRefreshResponse.self, from: response.body)
            tokens.accessToken = refreshed.accessToken
            if let refresh = refreshed.refreshToken { tokens.refreshToken = refresh }
            tokens.expiresAt = refreshed.expiresIn.map { now().addingTimeInterval($0) }
            try await replaceCredential(.oauth(tokens))
        }
        return tokens
    }

    private func refreshClaude(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        let tokens = try await claudeTokens(credential)
        let config = Self.claudeConfig
        let response = try await ClaudeUsageClient(httpClient: http).fetchUsage(accessToken: tokens.accessToken, config: config)
        let oauth = ClaudeOAuth(
            accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt?.timeIntervalSince1970,
            subscriptionType: tokens.extras["subscription_type"], rateLimitTier: tokens.extras["rate_limit_tier"]
        )
        var mapped = try ClaudeUsageMapper.mapUsageResponse(response, credentials: oauth)
        if let resets = await claudeResetGrantsLine(accessToken: tokens.accessToken) {
            mapped.lines.append(resets)
        }
        return (await claudeLivePlan(oauth, config: config) ?? mapped.plan, mapped.lines)
    }

    private func claudeLivePlan(_ oauth: ClaudeOAuth, config: ClaudeOAuthConfig) async -> String? {
        if let claudePlan, claudePlan.accessToken == oauth.accessToken { return claudePlan.plan }
        do {
            let response = try await ClaudeUsageClient(httpClient: http).fetchProfile(accessToken: oauth.accessToken, config: config)
            let profile = try ClaudeUsageClient.decodeProfile(response)
            guard let plan = ClaudeUsageMapper.formatLivePlan(profile: profile, credentials: oauth) else { return nil }
            claudePlan = (oauth.accessToken, plan)
            return plan
        } catch {
            AppLog.warn(LogTag.plugin("claude"), "plan lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The account's Codex tokens, refreshed and saved back to the vault first when they expire within
    /// `OAuthTokens.refreshMargin`.
    func codexTokens(_ credential: AccountCredential) async throws -> OAuthTokens {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        if tokens.needsRefresh(at: now()), let refreshToken = tokens.refreshToken {
            let refreshed = try await CodexUsageClient(http: http).refreshToken(refreshToken)
            tokens.accessToken = refreshed.accessToken
            if let refresh = refreshed.refreshToken { tokens.refreshToken = refresh }
            tokens.expiresAt = ProviderParse.jwtExpiry(refreshed.accessToken)
            try await replaceCredential(.oauth(tokens))
        }
        return tokens
    }

    private func refreshCodex(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        let tokens = try await codexTokens(credential)
        let accountID = tokens.extras["chatgpt_account_id"]
        let response = try await CodexUsageClient(http: http).fetchUsage(accessToken: tokens.accessToken, accountID: accountID)
        let resetCredits = await codexResetCredits(after: response, accessToken: tokens.accessToken, accountID: accountID)
        let mapped = try CodexUsageMapper.mapUsageResponse(response, resetCredits: resetCredits, now: now())
        return (mapped.plan, mapped.lines)
    }

    private func refreshCopilot(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .oauth(let tokens) = credential else { throw LoginError.invalidResponse }
        let response = try await CopilotUsageClient(http: http).fetchUsage(token: tokens.accessToken)
        try ProviderAuthRetry.requireSuccess(response, kind: .copilot)
        let mapped = try CopilotUsageMapper.map(response)
        return (mapped.plan, mapped.lines)
    }

    private func refreshGrok(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        let client = GrokUsageClient(httpClient: http)
        if tokens.needsRefresh(at: now()), let refreshToken = tokens.refreshToken {
            let response = try await client.refreshToken(refreshToken, clientID: GrokLogin.clientID)
            guard (200..<300).contains(response.statusCode), let refreshed = client.decodeRefreshResponse(response) else {
                throw ProviderError.failed(response)
            }
            tokens.accessToken = refreshed.accessToken
            if let refresh = refreshed.refreshToken { tokens.refreshToken = refresh }
            tokens.expiresAt = refreshed.expiresIn.map { now().addingTimeInterval($0) }
            try await replaceCredential(.oauth(tokens))
        }
        let usage = try await client.fetchCreditsConfig(accessToken: tokens.accessToken)
        let mapped = try GrokUsageMapper.mapCreditsConfig(usage)
        let settings = try? await client.fetchSettings(accessToken: tokens.accessToken)
        return (settings.flatMap(GrokUsageMapper.planName(from:)), mapped.lines)
    }

    private func refreshCursor(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        var tokens = try await cursorTokens(credential)
        let client = CursorUsageClient(http: http)
        let usageResponse = try await ProviderAuthRetry.fetch(
            token: tokens.accessToken,
            attempt: { try await client.fetchUsage(accessToken: $0) },
            refreshAccessToken: {
                tokens = try await refreshCursorTokens(tokens)
                return tokens.accessToken
            }
        )
        try ProviderAuthRetry.requireSuccess(usageResponse, kind: .cursor)
        guard let usage = ProviderParse.jsonObject(usageResponse.body) else {
            throw ProviderError.invalidResponse
        }
        let mapped = try await cursorUsage(usage, client: client, accessToken: tokens.accessToken)
        return (mapped.plan, mapped.lines)
    }

    private func refreshAntigravity(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        let client = AntigravityUsageClient(http: http)
        if tokens.needsRefresh(at: now()), let refreshToken = tokens.refreshToken {
            switch await client.refreshGoogleToken(refreshToken) {
            case .refreshed(let accessToken, let expiresIn):
                tokens.accessToken = accessToken
                tokens.expiresAt = now().addingTimeInterval(expiresIn)
                try await replaceCredential(.oauth(tokens))
            case .authFailed: throw ProviderError.signInExpired(.antigravity)
            case .unavailable: throw ProviderError.unavailable(AntigravityUsageClient.unavailableMessage)
            }
        }
        let codeAssist: Data? = if case .ok(let data) = await client.loadCodeAssist(token: tokens.accessToken) { data } else { nil }
        let project = codeAssist.flatMap(AntigravityUsageMapper.parseProject)
        let response = await client.cloudCodeAllHosts(
            path: AntigravityUsageClient.quotaSummaryPath,
            token: tokens.accessToken,
            userAgent: AntigravityUsageClient.clientUserAgent,
            body: project.map { ["project": $0] } ?? [:],
            isComplete: AntigravityUsageMapper.isCompleteSummary
        )
        switch response {
        case .authFailed: throw ProviderError.signInExpired(.antigravity)
        case .unavailable: throw ProviderError.unavailable(AntigravityUsageClient.unavailableMessage)
        case .ok(let bodies):
            guard let lines = AntigravityUsageMapper.parseQuotaSummaries(bodies) else { throw ProviderError.invalidResponse }
            return (codeAssist.flatMap(AntigravityUsageMapper.parseLoadCodeAssistPlan), lines)
        }
    }

    private func refreshOllama(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .apiKey(let key) = credential else { throw LoginError.invalidResponse }
        let client = OllamaUsageClient(http: http)
        let balance = try await client.fetchBalance(apiKey: key)
        try ProviderAuthRetry.requireSuccess(balance, kind: .ollama)
        let account = successBody(try? await client.fetchAccount(apiKey: key))
        let mapped = try OllamaUsageMapper.map(balanceBody: balance.body, accountBody: account)
        return (mapped.plan, mapped.lines)
    }

    private func refreshOpenCode(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .apiKey(let key) = credential else { throw LoginError.invalidResponse }
        let response = try await OpenCodeUsageClient(http: http).fetchUsage(apiKey: key)
        if response.statusCode == 403, OpenCodeUsageMapper.errorType(in: response) == "EntitlementError" {
            throw ProviderError.unavailable("No OpenCode Go subscription on this account.")
        }
        try ProviderAuthRetry.requireSuccess(response, kind: .opencodeGo)
        return (OpenCodeUsageMapper.plan, try OpenCodeUsageMapper.meterLines(response))
    }

    /// One OpenRouter endpoint's outcome: its `data` object, a rejected key, or the failure the card
    /// would show.
    private enum OpenRouterEndpoint {
        case data([String: Any])
        case keyRejected
        case failed(Error)
    }

    private func openRouterEndpoint(_ call: () async throws -> HTTPResponse) async -> OpenRouterEndpoint {
        do {
            let response = try await call()
            if ProviderAuthRetry.isAuthFailure(response) { return .keyRejected }
            try ProviderAuthRetry.requireSuccess(response, kind: .openrouter)
            guard let data = OpenRouterUsageMapper.dataObject(response.body) else {
                return .failed(ProviderError.invalidResponse)
            }
            return .data(data)
        } catch {
            return .failed(error)
        }
    }

    private func refreshOpenRouter(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .apiKey(let key) = credential else { throw LoginError.invalidResponse }
        let client = OpenRouterUsageClient(http: http)
        let credits = await openRouterEndpoint { try await client.fetchCredits(apiKey: key) }
        let keyInfo = await openRouterEndpoint { try await client.fetchKey(apiKey: key) }
        var lines: [MetricLine] = []
        var plan: String?
        if case .data(let data) = credits {
            lines += OpenRouterUsageMapper.creditsLines(from: data)
        }
        if case .data(let data) = keyInfo {
            let mapped = OpenRouterUsageMapper.keyMetrics(from: data)
            plan = mapped.plan
            lines += mapped.lines
        }
        if !lines.isEmpty { return (plan, lines) }
        // The key is only invalid when both endpoints reject it: OpenRouter gates some endpoints to
        // specific key types, so a lone 403 is a valid key that cannot read that endpoint.
        if case .keyRejected = credits, case .keyRejected = keyInfo {
            throw ProviderError.signInExpired(.openrouter)
        }
        let failures = [credits, keyInfo].compactMap { outcome -> Error? in
            if case .failed(let error) = outcome { return error }
            return nil
        }
        throw failures.first ?? ProviderError.invalidResponse
    }

    private func refreshZAI(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .apiKey(let key) = credential else { throw LoginError.invalidResponse }
        let client = ZAIUsageClient(http: http)
        let quota = try await client.fetchQuota(apiKey: key)
        try ProviderAuthRetry.requireSuccess(quota, kind: .zai)
        let subscription = successBody(try? await client.fetchSubscription(apiKey: key))
        let mapped = try ZAIUsageMapper.map(quotaBody: quota.body, subscriptionBody: subscription)
        return (mapped.plan, mapped.lines)
    }

    /// The body of a best-effort request, `nil` unless it succeeded: a failed plan lookup costs the
    /// plan, never the meters, and its error page never reaches a mapper.
    private func successBody(_ response: HTTPResponse?) -> Data? {
        guard let response, (200..<300).contains(response.statusCode) else { return nil }
        return response.body
    }

    /// Replaces the account's stored credential after a token refresh. The vault only replaces an
    /// existing entry, so a refresh that lands after the account was removed fails here instead of
    /// recreating the credential.
    func replaceCredential(_ credential: AccountCredential) async throws {
        try await loadOffMainActor { [vault, account] in try vault.update(credential, for: account.id) }
    }
}
