# Installing Overreach without a Mac

Building an iOS app needs Xcode, which only runs on macOS. GitHub's macOS runners do that for us: every push
to `main` runs the **Build IPA** workflow and publishes an installable `.ipa`. You then install it on your
iPhone from Windows (or Linux/macOS) with a sideloading tool and your own Apple ID.

> GitHub Actions macOS minutes are free for public repositories.

## 1. Download the IPA

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
- **To verify early:** whether HealthKit access survives free-account sideloading. The workflow embeds the
  HealthKit entitlement in the signature so the tool can carry it over; if Health permissions never appear
  in the app, the fallback is the paid Apple Developer account and TestFlight (phase 4, moved earlier).

## With a paid Apple Developer account (later)

The workflow can sign with your certificate and upload straight to TestFlight, so new builds arrive on your
iPhone (and Laura's) without cables or 7-day expiry. That change will get its own ADR.
