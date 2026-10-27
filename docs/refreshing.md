# Refreshing

## When data updates

- Every account refreshes together: once at launch, then every 5 minutes. There is no setting for the
  interval. Opening the panel does not start another pass.
- Accounts fetch in parallel, so a fast provider never waits for a slow one. Results that land close
  together are grouped so a burst shows as one update and is saved once.
- A new account refreshes as soon as you add it.
- The footer shows **Next update in …**. Click it, or press **⌘R**, to refresh now; this skips the cache.
- While an account is fetching, a spinner shows next to its name and in the footer.

## Caching

The last snapshot of every account is saved on disk and shown at launch, so you see your last-known
values before the first fetch finishes. A value counts as fresh for one interval after it was fetched
in the current session. A value from an earlier session is shown but refreshed on the first pass, so
a new app version never waits out the old interval.

## When a fetch fails

A failed refresh never wipes your data. The last good values stay on screen and a warning icon appears
next to the account's name; the account's right-click menu starts with the reason. The
error clears on the next successful refresh.

An account that failed is not tried again for one minute, so a burst of wakes cannot hammer a
provider that is down. A manual refresh ignores this wait.

An account that stops responding is given up on after two minutes. Its spinner stops, the warning reads
"Refresh timed out after 120s", and it is tried again on a later pass.

Once an account's values are more than two refresh cycles old, a clock appears next to its name, and
the account's right-click menu starts with their age. A successful refresh clears it.

## Expired sign-ins

OAuth accounts renew their own sign-in with the provider's refresh token. Cursor renews its sign-in
before the expiry it stored at sign-in. When a provider rejects the renewal, the account shows a
warning with the reason. Remove the account and add it again to sign in afresh.
