// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenUsage",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "OpenUsage", targets: ["OpenUsageApp"])
    ],
    dependencies: [
        // The de-facto standard recorder + global hotkey for Mac apps (System Settings-style field).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
        // In-app auto-updates (appcast + EdDSA-signed downloads). 2.9.4 fixes the update window opening
        // behind other apps for menu-bar (dockless) apps (sparkle-project/Sparkle#2889).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
        // Anonymous usage analytics and mandatory crash reporting (official first-party Swift SDK).
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.62.0")
    ],
    targets: [
        .target(
            name: "OpenUsage",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "PostHog", package: "posthog-ios")
            ],
            path: "Sources/OpenUsage",
            resources: [
                .copy("Resources/ProviderIcons")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "OpenUsageApp",
            dependencies: ["OpenUsage"],
            path: "Sources/OpenUsageApp",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "OpenUsageTests",
            dependencies: ["OpenUsage"],
            path: "Tests/OpenUsageTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
