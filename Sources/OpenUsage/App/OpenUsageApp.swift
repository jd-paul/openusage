import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let processStartedAt = ProcessInfo.processInfo.systemUptime
    private var container: AppContainer?
    private var statusItemController: StatusItemController?
    private var singleInstanceLock: SingleInstanceLock.Token?
    private let updater = UpdaterController()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.bootstrap()
        if let bundleID = Bundle.main.bundleIdentifier {
            switch SingleInstanceLock.acquire(bundleIdentifier: bundleID) {
            case .acquired(let token):
                singleInstanceLock = token
            case .alreadyRunning:
                SingleInstanceGuard.activateExistingInstance()
                NSApp.terminate(nil)
                return
            case .failed(let message):
                AppLog.error(.lifecycle, "single-instance lock unavailable: \(message)")
            }
        }
        NSApp.disableRelaunchOnLogin()
        AppearanceSetting.applyCurrent()
        Task { await finishLaunching() }
    }

    private func finishLaunching() async {
        let container = await AppContainer()
        self.container = container
        startDashboard(container)
    }

    private func startDashboard(_ container: AppContainer) {
        container.startRefreshing()
        statusItemController = StatusItemController(container: container, updater: updater)
        let launchDurationMS = Int((ProcessInfo.processInfo.systemUptime - processStartedAt) * 1_000)
        AppLog.info(.lifecycle, "launch to status item ready: \(launchDurationMS) ms")
        // Starts background update checks (release build only; dormant under the dev build and `swift run`).
        updater.start()
    }

    /// Flush pending snapshot writes and queued telemetry on quit. The SDK's lifecycle autocapture is
    /// off (the app emits its own daily rollups), so it won't auto-flush on termination.
    public func applicationWillTerminate(_ notification: Notification) {
        container?.dataStore.flushPendingSnapshotWork()
        container?.telemetry.flush()
    }
}
