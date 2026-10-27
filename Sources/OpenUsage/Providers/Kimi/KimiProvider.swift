import Foundation

@MainActor
final class KimiProvider: ProviderRuntime {
    let provider = Provider(
        id: "kimi",
        displayName: "Kimi",
        icon: .providerMark("kimi"),
        links: [
            ProviderLink(label: "Dashboard", url: "https://www.kimi.com/code/console")
        ]
    )

    let authStore: KimiAuthStore
    let usageClient: KimiUsageClient
    let now: @Sendable () -> Date

    init(
        authStore: KimiAuthStore = KimiAuthStore(),
        usageClient: KimiUsageClient = KimiUsageClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.authStore = authStore
        self.usageClient = usageClient
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        [
            .percent(id: "kimi.session", provider: provider, title: "Session")
                .exportingLimit("session", unit: "percent"),
            .percent(id: "kimi.weekly", provider: provider, title: "Weekly")
                .exportingLimit("weekly", unit: "percent"),
        ]
    }

    func hasLocalCredentials() async -> Bool {
        await loadOffMainActor { [authStore] in authStore.hasUsableCredentials() }
    }

    func refresh() async -> ProviderSnapshot {
        guard let file = await loadOffMainActor({ [authStore] in authStore.load() }) else {
            AppLog.info(LogTag.auth("kimi"), "no credentials, not logged in")
            return ProviderSnapshot.error(provider: provider, error: KimiAuthError.notLoggedIn)
        }

        // Refresh a dead (or nearly dead) access token first, persisting the rotation under the
        // official lock so the Kimi Code CLI picks it up too. QuotaWidget's protocol (which the
        // official CLI shares the lock with) documents an expired-rejected token as the refresh
        // trigger; an unexpired-but-rejected token is refreshed once on the 401/403 path below.
        var document = file.document
        if authStore.isExpired(file) {
            do {
                document = try await refreshCredentials(file, force: false)
            } catch KimiAuthError.refreshRejected {
                return ProviderSnapshot.error(provider: provider, error: KimiAuthError.sessionExpired)
            } catch {
                return ProviderSnapshot.error(provider: provider, error: error)
            }
        }

        let response: HTTPResponse
        do {
            response = try await usageClient.fetchUsage(accessToken: document.accessToken ?? "")
        } catch {
            return ProviderSnapshot.error(provider: provider, error: KimiUsageError.connectionFailed)
        }
        switch response.statusCode {
        case 200:
            break
        case 401, 403:
            do {
                let rotated = try await refreshCredentials(file, force: true)
                return await refresh(with: rotated)
            } catch {
                return ProviderSnapshot.error(
                    provider: provider,
                    error: (error as? KimiAuthError) ?? KimiAuthError.sessionExpired
                )
            }
        default:
            return ProviderSnapshot.error(provider: provider, error: KimiUsageError.requestFailed(response.statusCode))
        }

        do {
            let mapped = try KimiUsageMapper.map(response.body, now: now())
            return ProviderSnapshot.make(provider: provider, plan: mapped.plan, lines: mapped.lines, refreshedAt: now())
        } catch {
            return ProviderSnapshot.error(provider: provider, error: error)
        }
    }

    /// The usage fetch + map half of a refresh, given a (possibly rotated) credential document.
    private func refresh(with document: KimiCredentialDocument) async -> ProviderSnapshot {
        let response: HTTPResponse
        do {
            response = try await usageClient.fetchUsage(accessToken: document.accessToken ?? "")
        } catch {
            return ProviderSnapshot.error(provider: provider, error: KimiUsageError.connectionFailed)
        }
        guard response.statusCode == 200 else {
            return ProviderSnapshot.error(provider: provider, error: KimiAuthError.sessionExpired)
        }
        do {
            let mapped = try KimiUsageMapper.map(response.body, now: now())
            return ProviderSnapshot.make(provider: provider, plan: mapped.plan, lines: mapped.lines, refreshedAt: now())
        } catch {
            return ProviderSnapshot.error(provider: provider, error: error)
        }
    }

    private func refreshCredentials(_ file: KimiCredentialFile, force: Bool) async throws -> KimiCredentialDocument {
        try await authStore.refreshCredentials(file, force: force) { [usageClient] refreshToken in
            try await usageClient.refreshTokens(refreshToken: refreshToken)
        }
    }
}
