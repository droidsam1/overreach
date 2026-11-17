// swift-tools-version: 6.0
// OverreachKit: modules that need Apple frameworks (SwiftUI, SwiftData, HealthKit, Keychain).
// Dependency rules are documented in CLAUDE.md and ADR-0002. Features never depend on each other
// or on concrete data modules.
import PackageDescription

let core = "OverreachCore"

/// What every feature may depend on: domain protocols, analytics and the design system. Nothing else.
let featureDependencies: [Target.Dependency] = [
    .product(name: "Domain", package: core),
    .product(name: "Analytics", package: core),
    "DesignSystem",
]

let package = Package(
    name: "OverreachKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "HealthKitSource", targets: ["HealthKitSource"]),
        .library(name: "GarminSource", targets: ["GarminSource"]),
        .library(name: "AIKit", targets: ["AIKit"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "FeatureToday", targets: ["FeatureToday"]),
        .library(name: "FeatureWorkout", targets: ["FeatureWorkout"]),
        .library(name: "FeatureHistory", targets: ["FeatureHistory"]),
        .library(name: "FeatureTrends", targets: ["FeatureTrends"]),
        .library(name: "FeatureExercises", targets: ["FeatureExercises"]),
        .library(name: "FeaturePlan", targets: ["FeaturePlan"]),
        .library(name: "FeatureAssistant", targets: ["FeatureAssistant"]),
        .library(name: "FeatureSettings", targets: ["FeatureSettings"]),
        .library(name: "FeatureOnboarding", targets: ["FeatureOnboarding"]),
    ],
    dependencies: [
        .package(path: "../OverreachCore"),
    ],
    targets: [
        // MARK: Data
        .target(name: "Persistence", dependencies: [.product(name: "Domain", package: core)]),
        .target(name: "HealthKitSource", dependencies: [.product(name: "Domain", package: core)]),
        .target(name: "GarminSource", dependencies: [.product(name: "Domain", package: core)]),
        .target(name: "AIKit", dependencies: [
            .product(name: "Domain", package: core),
            .product(name: "Reports", package: core),
        ]),

        // MARK: UI foundation
        .target(name: "DesignSystem", dependencies: [.product(name: "Domain", package: core)]),

        // MARK: Features
        .target(name: "FeatureToday", dependencies: featureDependencies + ["AIKit"]),
        .target(name: "FeatureWorkout", dependencies: featureDependencies),
        .target(name: "FeatureHistory", dependencies: featureDependencies),
        .target(name: "FeatureTrends", dependencies: featureDependencies),
        .target(name: "FeatureExercises", dependencies: featureDependencies),
        .target(name: "FeaturePlan", dependencies: featureDependencies),
        .target(name: "FeatureAssistant", dependencies: featureDependencies + ["AIKit"]),
        .target(name: "FeatureSettings", dependencies: featureDependencies),
        .target(name: "FeatureOnboarding", dependencies: featureDependencies),

        // MARK: Tests
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", .product(name: "Domain", package: core)]),
        .testTarget(name: "FeatureWorkoutTests", dependencies: [
            "FeatureWorkout", "Persistence", .product(name: "Domain", package: core),
        ]),
        .testTarget(name: "FeatureSettingsTests", dependencies: [
            "FeatureSettings", "Persistence", .product(name: "Domain", package: core),
        ]),
        .testTarget(name: "FeatureHistoryTests", dependencies: [
            "FeatureHistory", "Persistence", .product(name: "Domain", package: core),
        ]),
        .testTarget(name: "FeatureTodayTests", dependencies: ["FeatureToday", .product(name: "Domain", package: core)]),
    ]
)
