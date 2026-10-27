# Kimi

Tracks Kimi Code (Moonshot AI) subscription usage: the rolling 5-hour session window and the
weekly quota, with reset countdowns — the same numbers the Kimi Code CLI's `/usage` shows.

## What it tracks

- **Session** — the rolling five-hour rate window (the `limits[]` entry whose window is 300 minutes).
- **Weekly** — the weekly quota total (the top-level `usage` object). Newer membership plans without
  a weekly window simply show the session meter.

## Where credentials come from

OpenUsage reads the Kimi Code CLI's existing OAuth login — nothing to paste:

- Current store: `~/.kimi-code/credentials/kimi-code.json` (or `$KIMI_CODE_HOME/credentials/kimi-code.json`)
- Legacy store: `~/.kimi/credentials/kimi-code.json` (or `$KIMI_SHARE_DIR/...`), used when the
  current store is absent

The credential file's other fields are preserved when a rotated token is written back.

## Endpoints it calls

- `GET https://api.kimi.com/coding/v1/usages` — quota windows (an undocumented internal API used by
  the Kimi Code CLI itself; response shapes fixture-tested in the test suite).
- `POST https://auth.kimi.com/api/oauth/token` — OAuth token rotation, only when the stored access
  token is expired or rejected. The rotation is persisted under Kimi Code's official
  `oauth/kimi-code.lock` directory lock (shared with the CLI, which re-reads the rotated file), so
  the two apps never fight over the login.

## Error states

- **Kimi not logged in** — no credential file found. Run `kimi` and `/login`.
- **Session expired** — the refresh token no longer grants. Run `kimi` and `/login` again.
- **Usage request failed** — a non-2xx status or a network failure; retry later.
