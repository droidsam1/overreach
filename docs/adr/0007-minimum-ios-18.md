# 0007 — Minimum deployment target: iOS 18

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

We prefer compatibility over the newest APIs, as long as security and implementation complexity are not
compromised. Candidates: iOS 17, 18 or 26.

## Decision

Target iOS 18.

- iOS 18 supports the same devices as iOS 17 (iPhone XS/XR and later), so we lose no hardware.
- SwiftData is considerably more mature on iOS 18 than on 17, and the new SwiftUI `Tab` API is available.
- iOS 26 would drop the iPhone XS/XR for little benefit to this app.

## Consequences

- Users must have updated to iOS 18 (most supported devices have).
- iOS 26-only APIs can be adopted behind `if #available` where valuable.
