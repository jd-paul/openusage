# Debugging

## Run a local build

```sh
./script/build_and_run.sh verify
```

The script stops the dev build if it is running, builds the package, stages `dist/OpenUsage.app`,
embeds Sparkle, signs the bundle with your Apple Development identity (ad hoc when none is installed),
launches it, and confirms the process is up. The dev bundle id is `com.robinebers.openusage.dev`, so
it keeps its own settings and Keychain items and runs beside an installed OpenUsage. It has no update
feed, so the Updates section does not show.

`./script/build_and_run.sh logs` launches the app and streams its log lines.

## Read the logs

OpenUsage logs through unified logging only, under the subsystem `OpenUsage`, one category per
subsystem tag (`refresh`, `cache`, `http`, `auth`, `menubar`, `updates`, `config`, `statusitem`,
`lifecycle`, `notifications`, and `plugin:<id>` and `auth:<id>` per account).

```sh
log stream --info --predicate 'subsystem == "OpenUsage"'
log stream --info --predicate 'subsystem == "OpenUsage" AND category == "refresh"'
log show --last 1h --info --predicate 'subsystem == "OpenUsage"'
```

Console.app shows the same lines; filter by subsystem. Debug-level lines exist in debug builds only
(`CONFIG=debug ./script/build_and_run.sh`) and need `--debug` instead of `--info`.

Every message passes `LogRedaction` before it is written: tokens, keys, emails, and home paths are
masked. A call site that logs a URL or response body must pre-redact it with `LogRedaction.redactURL`
or `bodyPreview`.

## Tests

```sh
swift test
swift test --filter CursorTokenRefreshTests
```
