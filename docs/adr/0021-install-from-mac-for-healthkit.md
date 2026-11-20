# ADR-0021: Install from a Mac with Xcode to get Apple Health on a free Apple ID

- Status: accepted
- Date: 2026-11-20

## Context

The IPA from the Build IPA workflow carries the HealthKit entitlement, but on an iPhone installed with
Sideloadly (Windows, free Apple ID) Today shows "Missing com.apple.developer.healthkit entitlement" (#60 made the
error visible). Sideloading tools re-sign with a provisioning profile from Apple; they do not ask Apple to enable
HealthKit on the App ID, so the profile lacks it and the signature drops it. SideStore's signing library has no
HealthKit mapping; Sideloadly only lets you add custom entitlements with a paid developer account.

Xcode's automatic signing does enable the capability on the App ID when the entitlements ask for it. Whether Apple
grants HealthKit to a free personal team is not documented clearly; developers report that it works.

## Decision

1. Offer `scripts/install-from-mac.command`: one command on any Mac with Xcode. It downloads the source and a
   pinned XcodeGen into a temporary folder, chooses the personal team from Xcode's accounts (asking when there
   are several), builds with `-allowProvisioningUpdates` and a bundle id derived from the team id, checks that the
   signature kept HealthKit, installs with `devicectl`, and deletes the folder. No Homebrew, no clone, no
   persistent install.
2. Sideloadly stays the documented route without a Mac; it works for everything except Apple Health.
3. If Apple refuses HealthKit for a free team, the script says so; the remaining option is the paid account and
   TestFlight (phase 4).

## Consequences

- Testers with access to a Mac get Health with a free Apple ID; renewing every 7 days still needs that Mac.
- The bundle id differs from the Sideloadly install, so the two are separate apps; data moves through a backup.
- The script depends on Xcode's preferences format and `devicectl` (Xcode 15+); it fails with a clear message when
  either changes.
