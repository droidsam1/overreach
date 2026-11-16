# 0008 — Generate the Xcode project with XcodeGen

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

`.xcodeproj` files are large, hard to review and a constant source of merge conflicts in open-source
projects. Signing settings (team id, bundle id) differ per contributor.

## Decision

- Describe the app target in `App/project.yml` and generate the project with XcodeGen. The generated
  `.xcodeproj` is git-ignored.
- Almost all code lives in Swift packages; the app target only contains the composition root.
- Per-developer signing lives in `App/Config/Local.xcconfig` (git-ignored), included optionally from
  `Base.xcconfig`. `Local.xcconfig.example` documents the keys.

## Consequences

- Contributors need `brew install xcodegen` and must run `xcodegen generate` after pulling changes to
  `project.yml`.
- Reviews only see the readable YAML; no pbxproj conflicts.
