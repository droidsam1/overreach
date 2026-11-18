// swift-tools-version: 6.0
// OverreachKit: modules that need Apple frameworks (SwiftUI, SwiftData, HealthKit, Keychain).
// Dependency rules are documented in CLAUDE.md and ADR-0002. Features never depend on each other
// or on concrete data modules.
import PackageDescription

let core = "OverreachCore"

/// What every feature may depend on (ADR-0014): value types, shared display helpers and the design system. Its own
/// presentation module is added per target. No Analytics: views don't run rules (also checked by SwiftLint, because
/// SwiftPM lets a target import the modules of its transitive dependencies).
let uiDependencies: [Target.Dependency] = [
    .product(name: "Domain", package: core),
    .product(name: "PresentationKit", package: core),
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
        // Generic components that take display values: no domain types (ADR-0014).
        .target(name: "DesignSystem"),

        // MARK: Features (UI only; logic comes from the presentation modules)
        .target(name: "FeatureToday", dependencies: uiDependencies + [
            "AIKit", .product(name: "TodayPresentation", package: core),
        ]),
        .target(name: "FeatureWorkout", dependencies: uiDependencies + [
            .product(name: "WorkoutPresentation", package: core),
        ]),
        .target(name: "FeatureHistory", dependencies: uiDependencies + [
            .product(name: "HistoryPresentation", package: core),
        ]),
        .target(name: "FeatureTrends", dependencies: uiDependencies),
        .target(name: "FeatureExercises", dependencies: uiDependencies + [
            .product(name: "ExercisesPresentation", package: core),
        ]),
        .target(name: "FeaturePlan", dependencies: uiDependencies + [
            .product(name: "PlanPresentation", package: core),
        ]),
        .target(name: "FeatureAssistant", dependencies: uiDependencies + ["AIKit"]),
        .target(name: "FeatureSettings", dependencies: uiDependencies + [
            .product(name: "SettingsPresentation", package: core),
        ]),
        .target(name: "FeatureOnboarding", dependencies: uiDependencies),

        // MARK: Tests
        .testTarget(name: "PersistenceTests", dependencies: [
            "Persistence", .product(name: "Domain", package: core), .product(name: "Fixtures", package: core),
        ]),
        // Backup model against the real backup service (Persistence); the rest of Settings is tested in Core.
        .testTarget(name: "SettingsIntegrationTests", dependencies: [
            "Persistence", .product(name: "Domain", package: core),
            .product(name: "SettingsPresentation", package: core),
        ]),
    ]
)
