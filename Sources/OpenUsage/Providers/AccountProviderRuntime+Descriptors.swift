import Foundation

extension AccountProviderRuntime {
    /// The account's metrics, each named by its card id. A metric that programs can read carries its
    /// limit resource for the `openusage` command (`exportingLimit`); the rest stay dashboard-only.
    var widgetDescriptors: [WidgetDescriptor] {
        Self.widgetDescriptors(for: account)
    }

    static func widgetDescriptors(for account: Account) -> [WidgetDescriptor] {
        let provider = provider(for: account)
        let prefix = account.cardID
        return switch account.kind {
        case .claude:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session", sessionStartSignal: .missingResetDate)
                    .exportingLimit("session", unit: "percent"),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly")
                    .exportingLimit("weekly", unit: "percent"),
                .percent(id: "\(prefix).sonnet", provider: provider, title: "Sonnet")
                    .exportingLimit("sonnet", unit: "percent"),
                .percent(id: "\(prefix).fable", provider: provider, title: "Fable")
                    .exportingLimit("fable", unit: "percent"),
                .boundedDollars(id: "\(prefix).extra", provider: provider, title: "Extra Usage", metricLabel: "Extra usage spent", limit: 100)
                    .exportingLimit("extraUsage", unit: "usd", source: .progressOrValue(kind: .dollars)),
                rateLimitResets(id: "\(prefix).rateLimitResets", provider: provider)
            ]
        case .codex:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session")
                    .exportingLimit("session", unit: "percent"),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly")
                    .exportingLimit("weekly", unit: "percent"),
                .percent(id: "\(prefix).spark", provider: provider, title: "Spark")
                    .exportingLimit("spark", unit: "percent"),
                .percent(id: "\(prefix).sparkWeekly", provider: provider, title: "Spark Weekly")
                    .exportingLimit("sparkWeekly", unit: "percent"),
                .values(id: "\(prefix).credits", provider: provider, title: "Extra Usage", metricLabel: "Credits")
                    .exportingLimit("credits", kind: .balance, unit: "credits", source: .value(kind: .count, label: "credits"))
                    .exportingLimit("creditValue", kind: .balance, unit: "usd", source: .value(kind: .dollars)),
                rateLimitResets(id: "\(prefix).rateLimitResets", provider: provider)
            ]
        case .cursor:
            [
                .percent(id: "\(prefix).usage", provider: provider, title: "Total Usage", metricLabel: "Total usage")
                    .exportingLimit("totalUsage", unit: "percent"),
                .percent(id: "\(prefix).auto", provider: provider, title: "Cursor Models")
                    .exportingLimit("autoUsage", unit: "percent"),
                .percent(id: "\(prefix).api", provider: provider, title: "Other Models")
                    .exportingLimit("apiUsage", unit: "percent"),
                .boundedDollars(id: "\(prefix).onDemand", provider: provider, title: "Extra Usage", metricLabel: "On-demand",
                                limit: 100, valueWord: "spent")
                    .exportingLimit("onDemand", unit: "usd", source: .progressOrValue(kind: .dollars)),
                .percent(id: "\(prefix).grokBot", provider: provider, title: "Grok Bot", metricLabel: "Grok Bot usage")
                    .exportingLimit("grokBot", unit: "percent"),
                .boundedCount(id: "\(prefix).requests", provider: provider, title: "Requests", limit: 500,
                              periodDurationMs: CursorUsageMapper.billingPeriodMs)
                    .exportingLimit("requests", unit: "requests"),
                .dollarBalance(id: "\(prefix).credits", provider: provider, title: "Credits", valueWord: "left")
                    .exportingLimit("credits", kind: .balance, unit: "usd", source: .value(kind: .dollars))
            ]
        case .antigravity:
            [
                .percent(id: "\(prefix).geminiPro", provider: provider, title: "Gemini 5h",
                         metricLabel: AntigravityMetric.sessionLabel, sessionStartSignal: .zeroUsage)
                    .exportingLimit("geminiSession", unit: "percent"),
                .percent(id: "\(prefix).geminiWeekly", provider: provider, title: "Gemini", metricLabel: AntigravityMetric.weeklyLabel)
                    .exportingLimit("geminiWeekly", unit: "percent"),
                .percent(id: "\(prefix).argonWeekly", provider: provider, title: "Argon", metricLabel: AntigravityMetric.argonWeeklyLabel)
                    .exportingLimit("argonWeekly", unit: "percent"),
                .percent(id: "\(prefix).claude", provider: provider, title: "Claude 5h",
                         metricLabel: AntigravityMetric.claudeLabel, sessionStartSignal: .zeroUsage)
                    .exportingLimit("nonGeminiSession", unit: "percent"),
                .percent(id: "\(prefix).claudeWeekly", provider: provider, title: "Claude", metricLabel: AntigravityMetric.claudeWeeklyLabel)
                    .exportingLimit("nonGeminiWeekly", unit: "percent")
            ]
        case .copilot:
            [
                .percent(id: "\(prefix).premium", provider: provider, title: "Credits", metricLabel: "Credits")
                    .exportingLimit("premiumCredits", unit: "credits", source: .progressOrValue(kind: .count)),
                .values(id: "\(prefix).extra", provider: provider, title: "Extra Usage")
                    .exportingLimit("extraUsage", unit: "count", source: .value(kind: .count)),
                .boundedCount(id: "\(prefix).chat", provider: provider, title: "Chat", limit: 0)
                    .exportingLimit("chat", unit: "percent"),
                .boundedCount(id: "\(prefix).completions", provider: provider, title: "Completions", limit: 0)
                    .exportingLimit("completions", unit: "percent")
            ]
        case .grok:
            [
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly", metricLabel: "Weekly limit")
                    .exportingLimit("weekly", unit: "percent"),
                .badge(id: "\(prefix).payAsYouGo", provider: provider, title: "Extra Usage", metricLabel: "Pay as you go")
            ]
        case .ollama:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session")
                    .exportingLimit("session", unit: "percent"),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly")
                    .exportingLimit("weekly", unit: "percent"),
                .percent(id: "\(prefix).monthly", provider: provider, title: "Monthly")
                    .exportingLimit("monthly", unit: "percent"),
                .dollarBalance(id: "\(prefix).purchasedCredits", provider: provider, title: "Extra Usage", metricLabel: "Purchased Credits", valueWord: "left")
                    .exportingLimit("purchasedCredits", kind: .balance, unit: "usd", source: .value(kind: .dollars))
            ]
        case .opencodeGo:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session", sessionStartSignal: .missingResetDate)
                    .exportingLimit("session", unit: "percent"),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly")
                    .exportingLimit("weekly", unit: "percent"),
                .percent(id: "\(prefix).monthly", provider: provider, title: "Monthly")
                    .exportingLimit("monthly", unit: "percent")
            ]
        case .openrouter:
            [
                .dollarBalance(id: "\(prefix).balance", provider: provider, title: "Balance", valueWord: "left")
                    .exportingLimit("balance", kind: .balance, unit: "usd", source: .value(kind: .dollars)),
                .values(id: "\(prefix).today", provider: provider, title: "Today"),
                .values(id: "\(prefix).week", provider: provider, title: "This Week"),
                .values(id: "\(prefix).month", provider: provider, title: "This Month")
            ]
        case .zai:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session")
                    .exportingLimit("session", unit: "percent"),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly")
                    .exportingLimit("weekly", unit: "percent"),
                .boundedCount(id: "\(prefix).webSearches", provider: provider, title: "Web Searches", limit: 0)
                    .exportingLimit("webSearches", unit: "searches")
            ]
        }
    }

    /// Each Claude and Codex account's Limit Resets row, whose popover is where the account's resets are
    /// claimed. The snapshot line keeps its "Rate Limit Resets" label.
    private static func rateLimitResets(id: String, provider: Provider) -> WidgetDescriptor {
        .values(id: id, provider: provider, title: "Limit Resets", metricLabel: "Rate Limit Resets",
                traySuffix: "resets", showsResetExpiries: true)
            .exportingLimit("rateLimitResets", kind: .balance, unit: "resets", source: .value(kind: .count, label: "available"))
    }
}
