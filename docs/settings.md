# Settings

Open Settings from the panel's **Options** menu or press **⌘,**. Every setting applies at once and
survives relaunch.

## General

| Setting | Control | What it changes |
|---|---|---|
| Launch at Login | switch | Registers OpenUsage as a login item, so it starts when you sign in to your Mac. |
| Global Shortcut | recorder | A keyboard shortcut that opens and closes the panel from any app. Click the field and press the keys. |

## Appearance

| Setting | Control | What it changes |
|---|---|---|
| Theme | System, Light, Dark | The panel's appearance. System follows macOS. |
| Time Format | Auto, 12-hour, 24-hour | How exact times read. Auto follows your macOS locale. |

## Usage display

| Setting | Control | What it changes |
|---|---|---|
| Show Usage As | Used, Left | Whether every bounded reading says `48% used` or `52% left`, on the dashboard and in the menu bar. |
| Reset Times | Countdown, Exact time | Whether reset labels read `Resets in 3h 25m` or `Resets today at 6:38 PM`. |

## Notifications

Three independent triggers, all off by default. Turning the first one on asks macOS for notification
permission.

| Setting | What it sends |
|---|---|
| Under 10% Remaining | The first time a metric with a limit drops under 10% left in its period. |
| Healthy Pace Changes | When a metric's pace worsens from on course (blue) to close to the limit (orange). |
| Near-Limit Pace Changes | When a metric's pace worsens from close to the limit (orange) to running out (red). |

Each notification names the trigger, the provider, and the metric, and fires once per metric per reset window.

## Privacy

| Setting | Control | What it changes |
|---|---|---|
| Help Make OpenUsage Better | switch | Whether the app sends the optional daily provider-refresh summaries described in [Privacy](privacy.md). The anonymous daily active ping and crash reports do not depend on this switch. |

## Updates

This section appears in the released build only; the dev build has no update feed.

| Setting | Control | What it changes |
|---|---|---|
| Check Automatically | switch | Checks for a new version about once an hour and shows the **Update Available** banner on the dashboard when one is found. |
| Beta Updates | switch | Adds pre-release builds to the checks. Turn it off to stay on your current version until the next stable release. |
| Check for Updates… | button | Checks now and opens the update window. |

See [Updates](updates.md).
