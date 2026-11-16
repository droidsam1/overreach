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
        .library(name: "Reports", targets: ["Reports"]),
    ],
    targets: [
        // Entities and protocols. Depends on nothing.
        .target(name: "Domain"),
        // Deterministic training analytics (load, progression, readiness).
        .target(name: "Analytics", dependencies: ["Domain"]),
        // Strong CSV import (phase 1).
        .target(name: "StrongImport", dependencies: ["Domain"]),
        // Markdown report shared with ChatGPT/Claude, and context for the in-app assistant.
        .target(name: "Reports", dependencies: ["Domain", "Analytics"]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "AnalyticsTests", dependencies: ["Analytics", "Domain"]),
        .testTarget(name: "ReportsTests", dependencies: ["Reports", "Domain"]),
    ]
)
