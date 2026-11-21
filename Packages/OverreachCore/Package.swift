// swift-tools-version: 6.0
// OverreachCore: pure Swift modules. No Apple-only frameworks, so it builds and tests on Linux too.
import PackageDescription

let package = Package(
    name: "OverreachCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Analytics", targets: ["Analytics"]),
        .library(name: "StrongImport", targets: ["StrongImport"]),
        .library(name: "GarminImport", targets: ["GarminImport"]),
        .library(name: "Reports", targets: ["Reports"]),
        .library(name: "AIExchange", targets: ["AIExchange"]),
        // Application layer (ADR-0035): reads sources once and answers questions several screens share.
        .library(name: "TrainingServices", targets: ["TrainingServices"]),
        // Presentation (ADR-0014): screen state, intents and texts. SwiftUI views in OverreachKit only render them.
        .library(name: "PresentationKit", targets: ["PresentationKit"]),
        .library(name: "ExercisesPresentation", targets: ["ExercisesPresentation"]),
        .library(name: "WorkoutPresentation", targets: ["WorkoutPresentation"]),
        .library(name: "HistoryPresentation", targets: ["HistoryPresentation"]),
        .library(name: "PlanPresentation", targets: ["PlanPresentation"]),
        .library(name: "SettingsPresentation", targets: ["SettingsPresentation"]),
        .library(name: "TodayPresentation", targets: ["TodayPresentation"]),
        .library(name: "OnboardingPresentation", targets: ["OnboardingPresentation"]),
        .library(name: "AssistantPresentation", targets: ["AssistantPresentation"]),
        // Generated test data (large anonymised history). Tests only; never linked by the app.
        .library(name: "Fixtures", targets: ["Fixtures"]),
    ],
    targets: [
        // Entities and protocols. Depends on nothing.
        .target(name: "Domain"),
        // Deterministic training analytics (load, progression, readiness).
        .target(name: "Analytics", dependencies: ["Domain"]),
        // Strong CSV import (phase 1).
        .target(name: "StrongImport", dependencies: ["Domain"]),
        // Garmin Connect Personal API responses → domain values (ADR-0022). Networking lives in OverreachKit.
        .target(name: "GarminImport", dependencies: ["Domain"]),
        // Markdown report shared with ChatGPT/Claude, and context for the in-app assistant.
        .target(name: "Reports", dependencies: ["Domain", "Analytics"]),
        // Versioned messages exchanged with AI chat apps (ADR-0017, docs/ai-exchange.md).
        .target(name: "AIExchange", dependencies: ["Domain", "Analytics"]),
        // Application layer (ADR-0035): one reading of the sources and one answer per shared training question.
        .target(name: "TrainingServices", dependencies: ["Domain", "Analytics"]),

        // Presentation layer (ADR-0014). One module per feature; they never import each other or SwiftUI.
        .target(
            name: "PresentationKit", dependencies: ["Domain", "Analytics"], path: "Sources/Presentation/PresentationKit"
        ),
        .target(
            name: "ExercisesPresentation",
            dependencies: ["Domain", "Analytics", "PresentationKit"],
            path: "Sources/Presentation/ExercisesPresentation"
        ),
        .target(
            name: "WorkoutPresentation",
            dependencies: ["Domain", "Analytics", "PresentationKit"],
            path: "Sources/Presentation/WorkoutPresentation"
        ),
        .target(
            name: "HistoryPresentation",
            dependencies: ["Domain", "Analytics", "TrainingServices", "PresentationKit"],
            path: "Sources/Presentation/HistoryPresentation"
        ),
        .target(
            name: "PlanPresentation",
            dependencies: ["Domain", "Analytics", "TrainingServices", "PresentationKit"],
            path: "Sources/Presentation/PlanPresentation"
        ),
        .target(
            name: "SettingsPresentation",
            dependencies: ["Domain", "Analytics", "PresentationKit"],
            path: "Sources/Presentation/SettingsPresentation"
        ),
        .target(
            name: "TodayPresentation",
            dependencies: ["Domain", "Analytics", "TrainingServices", "PresentationKit"],
            path: "Sources/Presentation/TodayPresentation"
        ),
        .target(
            name: "OnboardingPresentation",
            dependencies: ["Domain", "PresentationKit"],
            path: "Sources/Presentation/OnboardingPresentation"
        ),
        .target(
            name: "AssistantPresentation",
            dependencies: ["Domain", "TrainingServices", "PresentationKit", "AIExchange"],
            path: "Sources/Presentation/AssistantPresentation"
        ),

        // Generated test data shared by test targets in both packages.
        .target(name: "Fixtures", dependencies: ["Domain"]),

        .testTarget(name: "DomainTests", dependencies: ["Domain", "Fixtures"]),
        .testTarget(name: "AnalyticsTests", dependencies: ["Analytics", "Domain"]),
        .testTarget(name: "TrainingServicesTests", dependencies: ["TrainingServices", "Domain"]),
        .testTarget(name: "ReportsTests", dependencies: ["Reports", "Domain"]),
        .testTarget(name: "AIExchangeTests", dependencies: ["AIExchange", "Analytics", "Domain", "Fixtures"]),
        .testTarget(name: "StrongImportTests", dependencies: ["StrongImport", "Domain"]),
        .testTarget(
            name: "GarminImportTests",
            dependencies: ["GarminImport", "Domain", "HistoryPresentation", "Fixtures"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PresentationKitTests", dependencies: ["PresentationKit", "Domain"]),
        .testTarget(
            name: "ExercisesPresentationTests",
            dependencies: ["ExercisesPresentation", "PresentationKit", "Domain", "Fixtures"]
        ),
        .testTarget(
            name: "WorkoutPresentationTests",
            dependencies: ["WorkoutPresentation", "PresentationKit", "Domain", "Fixtures"]
        ),
        .testTarget(
            name: "HistoryPresentationTests",
            dependencies: ["HistoryPresentation", "PresentationKit", "Domain", "Fixtures"]
        ),
        .testTarget(
            name: "PlanPresentationTests",
            dependencies: ["PlanPresentation", "PresentationKit", "Domain", "Fixtures"]
        ),
        .testTarget(
            name: "SettingsPresentationTests",
            dependencies: ["SettingsPresentation", "PresentationKit", "Domain", "Fixtures"]
        ),
        .testTarget(
            name: "TodayPresentationTests",
            dependencies: ["TodayPresentation", "PresentationKit", "Domain", "Fixtures"]
        ),
        .testTarget(
            name: "OnboardingPresentationTests",
            dependencies: ["OnboardingPresentation", "Domain", "Fixtures"]
        ),
        .testTarget(
            name: "AssistantPresentationTests",
            dependencies: ["AssistantPresentation", "AIExchange", "PresentationKit", "Domain", "Fixtures"]
        ),
        .testTarget(name: "PerformanceTests", dependencies: ["Analytics", "StrongImport", "Domain", "Fixtures"]),
    ]
)
