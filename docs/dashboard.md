# Dashboard

The panel that opens from the menu bar icon. It is 340 pt wide and shows one provider after another,
each a header above a card.

## Providers and accounts

The header names the provider, and the account too when it has one with a name of its own
("Codex — Sunstory") that fits the line, with the account's plan at the right end of the line and the
provider's logo after it. Nothing on the line is ever cut short: a name that does not fit goes inside
the card with its plan, the way several accounts are shown, and an account named like its provider
reads as the provider alone, its plan on the header. The card holds every metric that has data, in the
order you set, one row each. When a provider has several accounts, each is named inside the card above
its rows, with its plan at the right.

When you have no accounts, the dashboard shows **Add Account**, which opens the provider chooser.

## Rows

A row is the metric's label, a bar, its value, and its reset, in fixed columns, so every bar in the
panel starts and ends at the same place. The bar fills with what is left (or what is used, under the
Used setting); the value reads `52%`, `$12`, or `320`; the reset reads `1h 26m` or `6d 22h`, or
`Wed 4 PM` under the exact-times setting, and `soon` once it is due. **Settings → Usage Display**
chooses between used and left, and between countdowns and exact times. Rows with a reset tick every
30 seconds, so countdowns stay live between refreshes.

The bar's colour follows how much is used, never the pace: blue, orange once 75% is used, red once 90%
is. The value takes the bar's colour once the bar is orange or red. Once a balance is spent, the bar
stays red. A session window with nothing spent in it yet shows a full bar and no reset. The colours come
from the system palette, so they follow light, dark, and accessibility settings.

Your burn rate shows as a flame before the value while you are using the limit faster than it resets:
orange when you are on course to land within the last 10%, red when you are on course to run out before
the reset. The same pace drives the [notifications](settings.md).

A metric without a limit (a balance, a day's spend, a status) shows its value where the bar would be,
such as `$12.40 left`. A metric the provider has not reported is hidden.

## Resets

Claude and Codex accounts show a **Limit Resets** row with the number of available rate-limit resets
while they have any. Rest the pointer on the count for a moment to see when each reset expires; it is
the one thing on a row that reacts to the pointer. To spend one, choose **Use** on it, then **Reset**.

A spinner after an account's name means it is refreshing. A warning icon means its last refresh failed,
and a clock means its values are more than two refresh cycles old; the account's right-click menu
starts with the reason.

## Right-click menus

- A provider's card: **Refresh**, **Manage Accounts…**, and the provider's links, such as
  **Status Page** and **Usage Dashboard**.
- An account: **Refresh**, **Rename**, **Edit Account…**, and **Share Screenshot**. If the account
  shows a warning or stale icon, the menu starts with the reason. **Show Hidden Metrics** appears when
  you have hidden any.
- A metric: **Star for Menu Bar** (or **Unstar**) and **Hide**. Hiding a metric, here or on the
  Accounts screen, also takes its star off the menu bar. Starring a hidden metric shows it again.

On a card with one account, the header's menu combines the provider and account items.

## Reordering

Drag a provider by its header, an account by its name inside the card, or a metric by its row. A new provider goes to the
bottom of the dashboard and of the Accounts list, and a new account goes to the bottom of its
provider's accounts. The app never sorts providers or accounts for you.

Press **⌘Z** to undo the last layout change (hiding or showing a metric, reordering, starring). Undo is
per session.

## Rename

Double-click an account's name, or choose **Rename** from its menu. The field opens with the whole
name selected. Return or a click elsewhere saves; Esc cancels.

## Share

Copy a PNG of one provider's header and card to the clipboard: while the pointer is on the provider,
its logo becomes a camera button; click it, or right-click and choose **Share Screenshot**. The image
shows the header and card at rest, follows your light or dark appearance, and carries a small OpenUsage
mark at the bottom. An account named by its email reads as its provider alone, so the email never
leaves the panel.

## Update banner

When a scheduled update check finds a new version, an **Update Available** card sits above the
provider cards. **Install Update** opens the update window; the ✕ snoozes the card until the next
check. See [Updates](updates.md).

## Footer

The bar pinned to the bottom of the panel. On the left: the app version and a live
**Next update in …** countdown you can click (or press **⌘R**) to refresh now. On the right: the
**Options** menu with **Accounts**, **Settings**, **Report an Issue…**, **About OpenUsage**, and
**Quit OpenUsage**.

## Keyboard

| Key | Action |
|---|---|
| Return | From the dashboard, open Accounts; from an account's page, return to the list; from the list or Settings, return to the dashboard |
| Esc | Same as Return one level up; from the dashboard, close the panel |
| ⌘Z | Undo the last layout change |
| ⌘R | Refresh now (skips the cache) |
| ⌘, | Open or close Settings |

A global shortcut, recorded in Settings, toggles the panel from anywhere.

## Closing

Closing the panel returns to the dashboard, scrolled to the top.
