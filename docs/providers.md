# Providers

How each provider signs in and what its card shows. Every value comes from the provider's own API.
OpenUsage computes no spend from logs and applies no model pricing; a metric the provider does not
report stays hidden.

| Provider | Sign-in | Card shows |
|---|---|---|
| Claude | Browser (claude.ai OAuth) | Session, Weekly, Sonnet, Fable, Extra Usage, Rate Limit Resets |
| Codex | Browser (OpenAI OAuth), with a device-code fallback | Session, Weekly, Spark, Spark Weekly, Extra Usage, Rate Limit Resets |
| Cursor | Browser (cursor.com) | Total Usage, Cursor Models, Other Models, Extra Usage, Grok Bot, Requests, Credits |
| Antigravity | Browser (Google OAuth) | Gemini 5h, Gemini, Argon, Claude 5h, Claude |
| Copilot | Device code (GitHub) | Credits, Extra Usage, Chat, Completions |
| Grok | Device code (xAI) | Weekly, Extra Usage |
| Ollama | API key | Session, Weekly, Monthly, Extra Usage |
| OpenCode | API key | Session, Weekly, Monthly |
| OpenRouter | Management API key | Balance, Today, This Week, This Month |
| Z.ai | API key | Session, Weekly, Web Searches |

## Claude

Sign in through claude.ai in your browser. The sheet also accepts a pasted code if your browser shows
one instead of returning to the app. The card reads `/api/oauth/usage` for the session, weekly,
Sonnet, and Fable windows and the extra-usage spend, and `/api/oauth/profile` once per token for the
plan badge (Pro, Max, Team). Team seats get no weekly window from the API, so none shows.

The ↺ tag counts the account's available rate-limit resets. Hover it to see when each expires; choose
**Use**, then **Reset** to spend one.

## Codex

Sign in through OpenAI in your browser. When the app cannot listen on port 1455 for the browser's
return, it offers a device code instead. The card reads `/backend-api/wham/usage` for the session and weekly windows, the Spark
windows, and extra-usage credits, and the plan badge (Plus, Pro, Team, Business). Rate-limit reset
credits work like Claude's ↺ tag.

## Cursor

Sign in through cursor.com in your browser. The card reads Cursor's dashboard API for Total Usage,
Cursor Models (auto), Other Models (API), on-demand Extra Usage, Grok Bot, Requests, and Credits, and
the plan badge. Cursor stores the sign-in's expiry and renews it before then.

## Antigravity

Sign in with Google in your browser. The card reads the Cloud Code quota API for the Gemini and Claude
pools (5-hour and weekly windows) and the Argon weekly window, and shows the plan badge (Pro, Ultra,
Ultra Lite).

## Copilot

Sign in with a GitHub device code. The card reads `/copilot_internal/user` for premium credits,
extra-usage spend, and the chat and completion counts, and the plan badge.

## Grok

Sign in with an xAI device code. The card reads the Grok settings and billing endpoints for the weekly
shared pool, pay-as-you-go extra usage, and the plan badge.

## Ollama

Paste an API key from [ollama.com/settings/keys](https://ollama.com/settings/keys). The card reads the
balance API for the session, weekly, and monthly windows that your plan has, plus purchased credits,
and the plan badge.

## OpenCode

Paste an API key from the [OpenCode console](https://opencode.ai/console). The card reads
`/zen/go/v1/usage` for the session, weekly, and monthly caps, and shows a Go plan tag.

## OpenRouter

Paste a **Management** key from
[openrouter.ai/settings/management-keys](https://openrouter.ai/settings/management-keys). A regular
inference key cannot read the balance. The card reads `/api/v1/credits` for the balance and
`/api/v1/key` for today's, this week's, and this month's spend. Balance is the default menu-bar star.

## Z.ai

Paste an API key from the [Z.ai key list](https://z.ai/manage-apikey/apikey-list). The card reads the
GLM Coding Plan subscription and quota endpoints for the session and weekly windows, the web-search
quota, and the plan badge.

## Errors

A warning icon next to the account's name means the last refresh failed; hover it for the reason.
"Not logged in" or "sign in again" means the provider rejected the stored credential: remove the
account and add it again. "Rate limited" and HTTP errors clear on a later refresh. See
[Refreshing](refreshing.md).
