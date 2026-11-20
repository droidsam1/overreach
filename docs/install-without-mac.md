# Installing Overreach without a Mac

Building an iOS app needs Xcode, which only runs on macOS. GitHub's macOS runners do that for us: every push
to `main` runs the **Build IPA** workflow and publishes an installable `.ipa`. You then install it on your
iPhone from Windows (or Linux/macOS) with a sideloading tool and your own Apple ID.

> GitHub Actions macOS minutes are free for public repositories.

Testers should use the IPA attached to the latest
[GitHub Release](https://github.com/droidsam1/overreach/releases) and follow the
[tester guide](beta-guide.es.md) (Spanish).

## 1. Download the IPA

To try the latest development build instead:

1. Open the repository on GitHub → **Actions** → **Build IPA**.
2. Open the latest successful run (or press **Run workflow** to build one now).
3. Download the **Overreach-ipa** artifact and unzip it. You get `Overreach-<commit>.ipa`.

## 2. Install it on your iPhone

Pick one tool:

- **Sideloadly** (Windows/macOS): connect the iPhone by cable, drag the `.ipa` in, enter your Apple ID, press
  Start.
- **AltStore** (Windows/macOS): install AltServer on the PC and AltStore on the iPhone, then open the `.ipa`
  from AltStore. With AltServer running on the same Wi-Fi, AltStore refreshes the app automatically before it
  expires.

Then, on the iPhone: **Settings → General → VPN & Device Management →** trust your Apple ID, and enable
**Settings → Privacy & Security → Developer Mode** if iOS asks for it.

## Limits with a free Apple ID

- The app stops opening after **7 days** and must be refreshed (AltStore can automate it).
- At most 3 sideloaded apps at a time.
- iCloud/CloudKit and TestFlight are not available (ADR-0004).
- **Apple Health does not work.** Verified with Sideloadly on Windows: the app shows "Missing
  com.apple.developer.healthkit entitlement". The IPA carries the entitlement, but the provisioning profile the
  tool gets from Apple does not enable HealthKit, so the re-signed app loses it (ADR-0021). Everything else
  works. For Health, install from a Mac (below) or use the paid account.

## With Apple Health: install from a Mac

`scripts/install-from-mac.command` builds the app with Xcode and signs it with your own Apple ID, so Xcode asks
Apple for a HealthKit-enabled App ID. It needs only Xcode, opened once, with your Apple ID added in
**Settings → Accounts**, and the iPhone on a cable. In Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/droidsam1/overreach/main/scripts/install-from-mac.command | bash
```

(or double-click the file in a clone). It downloads the source and a pinned XcodeGen into a temporary folder,
picks your personal team (it asks if Xcode has several accounts, e.g. a work one), builds with a bundle id tied to
that team, reports whether the signature kept HealthKit, installs with `devicectl` and deletes the folder. Run it
again within 7 days to renew; the bundle id is the same, so data is kept. Apps installed this way and with
Sideloadly are different apps: move data with a backup.

## With a paid Apple Developer account (later)

The workflow can sign with your certificate and upload straight to TestFlight, so new builds arrive on your
iPhone (and Laura's) without cables or 7-day expiry. That change will get its own ADR.
