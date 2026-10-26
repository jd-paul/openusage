# Dashboard

The panel that opens from the menu bar icon. It is 340 pt wide and has one card per provider.

## Cards

Each card shows the provider's mark and name, then one block per account. An account block shows the
account's name with its plan as a tag on the right, then every metric that has data, in the order you
set. When a provider has only one account, the card's header shows that account's name next to the
mark, with its tags on the right, and the metrics follow straight below.

When you have no accounts, the dashboard shows **Add Account**, which opens the provider chooser.

## Metrics

A metric with a limit (session, weekly, a capped balance) shows a bar with a reading such as
`52% left` or `48% used`, and a reset time such as `Resets in 3h 25m` or `Resets today at
6:38 PM`. **Settings → Usage Display** chooses between used and left, and between countdowns and
exact times. Rows with a reset date tick every 30 seconds, so countdowns stay live between refreshes.

The bar's colour is a verdict on the whole window, from your current burn rate:

- Blue while you are on course to finish with at least 10% to spare.
- Orange when you are projected to land inside the last 10%. The row adds a `~3% spare` note.
- Red when you are projected to run out before the reset, or to finish with nothing to spare. The row
  adds a flame with the projected run-out time.

Bars without a reset window, and windows too young to project, colour by level instead: orange once 80%
is used, red once 10% or less is left. Once a balance is spent, the bar stays red and reads
`Limit reached`. The colours come from the system palette, so they follow light, dark, and
accessibility settings.

A metric without a limit (a balance, a day's spend) shows as one line, such as `$12.40 left`. A metric
the provider has not reported shows nothing; a row with no data is hidden.

Claude and Codex accounts show a ↺ tag with the number of available rate-limit resets. It turns orange
when the soonest one expires within 7 days and red within 48 hours. Hover or click the tag to see when
each reset expires. To spend one, hover its row, choose **Use**, then **Reset**.

A warning icon next to an account's name means its last refresh failed; hover it for the reason. An
**Outdated** tag means the values are more than two refresh cycles old; hover it for their age.

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

Drag a card by its header, an account by its name, or a metric by its line. A new provider goes to the
bottom of the dashboard and of the Accounts list, and a new account goes to the bottom of its
provider's accounts. The app never sorts providers or accounts for you.

Press **⌘Z** to undo the last layout change (hiding or showing a metric, reordering, starring). Undo is
per session.

## Rename

Double-click an account's name, or choose **Rename** from its menu. The field opens with the whole
name selected. Return or a click elsewhere saves; Esc cancels.

## Share

Copy a branded PNG of one provider's card to the clipboard: right-click the card and choose
**Share Screenshot**. The image shows the card as you see it, follows your light or dark appearance,
and carries a small OpenUsage mark at the bottom.

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
