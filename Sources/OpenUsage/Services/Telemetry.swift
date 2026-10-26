import Foundation
import PostHog

/// The transport seam telemetry is emitted through. Abstracted from PostHog so the recorder's
/// daily-rollup/dedup logic can be unit-tested against a fake sink. The optional-analytics toggle
/// lives in `TelemetryRecorder`; the sink never opts out, because daily activity and crash reports
/// are mandatory.
@MainActor
protocol TelemetrySink: AnyObject {
    func capture(_ event: String, _ properties: [String: Any])
    func flush()
}

/// Anonymous PostHog sink. Constructing it starts the process-global SDK, so only the app entry point
/// does; everything else receives it as a `TelemetrySink`. No `identify()`/`group()`/`alias()`,
/// `personProfiles = .never`, and only IDs/counts/enums are ever sent — never free-form error messages.
@MainActor
final class PostHogTelemetrySink: TelemetrySink {
    /// The project token baked into the build: a client-side, write-only key that ships in every
    /// distributed binary, like any analytics SDK key, so it is safe to commit. The host is region-bound
    /// — a US token will not ingest against the EU host.
    private static let token = "phc_vGEqXEpQNwViyKnMNWvmKWpv8XxMT3yaeYi6gfidr4nf"
    /// US cloud. Switch to "https://eu.i.posthog.com" only with an EU-region project token.
    private static let host = "https://us.i.posthog.com"

    init() {
        let config = PostHogConfig(projectToken: Self.token, host: Self.host)
        // Fully anonymous: no person profiles, no anonymous->identified merge.
        config.personProfiles = .never
        // We use no feature flags and emit our own daily rollups, so skip both startup fetches/autocapture.
        config.preloadFeatureFlags = false
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        // Daily activity and crash reporting are mandatory, so the transport never opts out.
        config.optOut = false
        // Crash / uncaught-exception autocapture is always enabled, whatever the optional-analytics
        // preference says (anonymous `$exception` events, sent on the NEXT launch after a crash). It
        // captures Mach exceptions, POSIX signals, and uncaught NSExceptions; Swift traps may surface as
        // a bare `SIGTRAP` without the message — the symbolicated stack (dSYMs uploaded from
        // release.yml) is what makes them actionable.
        // NOTE: this local flag is necessary but NOT sufficient — posthog-ios also gates the integration
        // on a SERVER-side switch (remote config `errorTracking.autocaptureExceptions`). "Exception
        // autocapture" must be enabled in the PostHog project settings, and because the SDK reads it from
        // cache at init, capture arms on the *second* launch after enabling (first launch fetches+caches).
        // Never reference sessionReplay / surveys / captureElementInteractions / tracingHeaders here:
        // they do not exist on a macOS target.
        config.errorTrackingConfig.autoCapture = true
        PostHogSDK.shared.setup(config)
        // Clear a persisted SDK opt-out so both mandatory signals can send.
        PostHogSDK.shared.optIn()

        // Super properties ride on every subsequent event (anonymous, non-PII).
        PostHogSDK.shared.register([
            "app_version": AppInfo.version,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString
        ])
        AppLog.info(.config, "telemetry initialized")
    }

    func capture(_ event: String, _ properties: [String: Any]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    func flush() {
        PostHogSDK.shared.flush()
    }
}
