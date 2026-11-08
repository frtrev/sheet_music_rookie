# Sheet Music Rookie release package

> Apple registration verified on 7 November 2026: Xcode automatic signing produced an App Store provisioning profile for `com.neotheone.sheetmusicrookie`. A newly signed IPA is in `build/ios/ipa/`; see `reports/new-bundle-registration.json`. No build was uploaded. The historical files under `release/ios/` remain the older snapshot.

> Identifier update: source now uses `com.neotheone.sheetmusicrookie` on iOS and Android. Existing release packages and verification reports below retain the previous identifier and must be regenerated before upload. Register/select the new identifier in the store accounts and obtain matching iOS provisioning. Changing the identifier installs a separate app; export any sheets needed from older test installations before switching.

> Source update: inline lyric editing, the remembered tapped-note speaker toggle, measure repeat/volta controls, the Sheets manager, and Spanish language support were added after the release snapshot documented below. The existing packaged binaries and store screenshots predate these features. Run `./scripts/prepare_store_release.sh` again before submitting the updated app.

Prepared 6 November 2026. Version remains **1.0.0+1**. Do not upload a build number already used in either portal; set the next number in pubspec.yaml or pass Flutter build flags. Bundle identifiers and Apple signing team are preserved.

**Read reports/final-status.md for actual results and remaining blockers.** This package is not a claim that the app has been submitted or approved. No store declarations, uploads, Git pushes, or website publication are automatic.

## Files to upload

| Portal | Files |
|---|---|
| Google Play | A correctly upload-key-signed `android/app-release.aab` when available; `store_assets/android/phone/*.png`; separate `tablet_7` and `tablet_10` folders; `android/icon/google_play_icon.png`; `android/feature_graphic/feature_graphic.png` |
| App Store Connect | Signed archive/IPA under `ios/` when available, via Xcode Organizer/Transporter; `store_assets/ios/iphone_other_required/*.png`, `iphone_large/*.png`, and `ipad/*.png` |
| Listing text | `store_metadata/google/` and `store_metadata/apple/`: separate ready-to-copy TXT fields and JSON records |
| Privacy/rating forms | Review `store_metadata/privacy-and-ratings-recommendations.md` and `reports/privacy-compliance.md`; owner submits the final answers |

Canonical assets live in `../store_assets/`; automation copies them into this package's `store_assets/` and `store_metadata/`. Reports include per-image dimensions, actual PNG color type, file size, SHA-256 and pass/fail status. **A passing image report checks technical properties; visual QA and successful capture are also required.** Empty/missing groups fail the validator.

## Screenshot groups

All final screenshots are PNG at native capture resolution. Normalization only flattens alpha to opaque RGB; it does not resize, crop, or stretch.

| Folder | Upload slot / device | Exact portrait pixels |
|---|---|---|
| ios/iphone_other_required | iPhone with Dynamic Island (medium display), iPhone 17 Pro | 1206 × 2622 |
| ios/iphone_large | iPhone with Dynamic Island (large display), iPhone 17 Pro Max | 1320 × 2868 |
| ios/ipad | iPad 13-inch, iPad Pro 13-inch (M5) | 2064 × 2752 |
| android/phone | Android phone | 1080 × 1920 |
| android/tablet_7 | Android ~7-inch, 320 dpi | 1200 × 1920 |
| android/tablet_10 | Android ~10-inch, 300 dpi | 1600 × 2560 |

Six captures per group: home, clef selection, octave range selection, saved sample composition, tempo controls, and insert-note controls. The original C-major exercise is saved through the app's real storage service. No fake listening indicator or synthetic feature UI is added to production. Microphone listening screenshots are deliberately not required by this capture set; physical microphone validation remains separate. The unavailable card provides a Retry action after permission is enabled in system Settings.

Apple's current reference uses Dynamic Island display labels and requires medium iPhone plus 13-inch iPad for this universal app. Large iPhone is additionally supplied as requested. New iPhone Duo requirements apply from April 2027 for iOS 27.1+ SDK builds; recheck official documentation for future submissions. Google phone assets are 9:16 and include at least four images at 1080×1920 for the documented promotional recommendation. Tablet assets are separate actual Android layouts.

## Website URLs (after owner-approved publication)

- Marketing: https://frtrev.github.io/sheet-music-rookie/
- Privacy: https://frtrev.github.io/sheet-music-rookie/privacy-policy/
- Support: https://frtrev.github.io/sheet-music-rookie/support/
- Existing publisher: Francisco Trevino · NeoTheOne
- Existing contact: ftrevino@yahoo.com

`website/frtrev.github.io/` contains the full staged static site, preserving other apps and shared CSS. `scripts/prepare_release_website.py` rebuilds it against the existing website checkout and adds product/privacy/support pages and directory links. Website changes must be reviewed, committed and deployed in the website repository by the owner. Verify the new URLs over HTTPS before using them in store forms. No framework build is needed for this static HTML/CSS site. Local link verification is recorded in reports/website-links.json.

## One-time setup

Use the installed Apple Silicon Flutter SDK, Xcode, Android Studio JBR, Android SDK/API 36 and a working Python 3/Swift toolchain. This preparation used Flutter 3.47.5, Dart 3.13.4 and Xcode 27.0/iOS SDK 27.0. No paid service is needed. SDKs may need writable caches and package-network access.

1. Run `flutter doctor -v`. Keep Xcode and Android command line tools/licences configured.
2. Create dedicated iOS simulators with names beginning `SMR Store ` and matching `scripts/store_targets.json`, using Xcode's Devices and Simulators or `xcrun simctl create`. Use clean capture simulators so unrelated system permission dialogs cannot cover the app. Do not erase personal simulators.
3. Create a dedicated Android emulator named `smr_phone` with the installed `system-images;android-36;google_apis_ps16k;arm64-v8a` image (or an equivalent supported API 36 ARM64 image). Run `emulator -avd smr_phone`. Capture uses the explicit emulator ID and refuses a personal Android device. The capture script sets exact native framebuffer size and density separately for each group; the ~7/~10-inch layouts meet tablet dp widths. It never resizes screenshots after capture.
4. Configure a real Android upload key securely. If an app is already enrolled in Play App Signing, use its registered upload key. **Do not generate a replacement without checking the existing Play app.**
5. Configure the retained Apple team `C2M32YF6V7`, app identifier `com.sheetmusicrookie.sheetMusicRookie`, distribution certificate and provisioning profile in Xcode. Complete Apple Developer agreements and account access as needed.

### Android signing

Create ignored `android/key.properties` locally, using the existing approved key:

```properties
storeFile=/absolute/path/to/your/existing-upload-key.jks
storePassword=YOUR_LOCAL_SECRET
keyAlias=YOUR_EXISTING_ALIAS
keyPassword=YOUR_LOCAL_SECRET
```

Never commit the file or key. Automation does not print/read its contents into reports. Standard release tasks fail if any field is missing. No debug-key fallback exists. With valid configuration:

```sh
flutter build appbundle --release
```

The default build uses minification and resource shrinking. Upload the resulting signed AAB only after confirming its signing certificate matches the registered upload key. No ready-to-upload AAB is promised when signing is absent.

### iOS archive

```sh
flutter build ipa --release
```

Open `build/ios/archive/Runner.xcarchive` in Xcode Organizer to validate distribution, privacy report, signing and export compliance. A no-codesign build/archive, if supplied for verification, is **not uploadable**. Review certificate/provisioning/account errors in the report rather than changing bundle/team identity.

## Repeat the preparation

Set explicit dedicated device IDs, then run:

```sh
export IOS_MEDIUM_DEVICE='<dedicated iPhone 17 Pro UDID>'
export IOS_LARGE_DEVICE='<dedicated iPhone 17 Pro Max UDID>'
export IOS_IPAD_DEVICE='<dedicated iPad Pro 13-inch M5 UDID>'
export ANDROID_CAPTURE_DEVICE='emulator-5554'
./scripts/prepare_store_release.sh
```

Optional `WEBSITE_SOURCE=/absolute/path/to/frtrev.github.io` overrides the sibling website path. The script attempts every independent phase, records failures/blocked device groups, and exits nonzero if any phase is incomplete. Missing credentials or devices never silently pass. It runs pub get, analyze, tests, signed release builds, graphics, metadata, dependency inventory, native captures, strict image validation and website/link checks, then packages outputs. Capture runs real UI with integration-test code; a loopback-only host bridge executes `simctl io screenshot` or `adb exec-out screencap`. The bridge is terminated after each group. Never use integration-test targets as store release entrypoints.

Individual commands:

```sh
./scripts/capture_store_screenshots.sh iphone_other_required "$IOS_MEDIUM_DEVICE"
python3 scripts/validate_store_assets.py
python3 scripts/generate_store_metadata.py
python3 scripts/prepare_release_website.py
python3 scripts/check_website_links.py release/website/frtrev.github.io
```

Review every screenshot for app identity, visual correctness, system dialogs and keyboards. Exact dimension checks alone do not prove content readiness. Refresh `scripts/store_targets.json` only after checking current official sources:

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://support.google.com/googleplay/android-developer/answer/9866151?hl=en
- https://support.google.com/googleplay/android-developer/answer/11926878?hl=en

## Manual submission gates

Confirm store account records/unique identifiers, available build number, upload/distribution signing, artwork/content rights, target audience, age rating, privacy form answers and encryption export compliance. Validate actual microphone allowance/denial/recovery, singing detection, audio playback, imports, save/reopen across process restart and background behavior on physical iOS and Android devices. Optional fixture-based skipped tests are documented in final-status.md. Approve and publish website changes, verify live URLs, then upload listings/binaries. No publication occurs from these scripts.

The website package also contains `website/changes/`, `website/manifest.json`, and `website/website.patch` for reviewing just the changed files. `python3 scripts/apply_release_website.py --target /path/to/frtrev.github.io` applies local changes only and refuses to overwrite files changed since packaging. It never commits or pushes.

On this Mac, `source release/capture-devices.env` sets the dedicated devices created during preparation. Start the `smr_phone` AVD and verify that its current ID is still `emulator-5554` before using it. The capture workflow changes only that dedicated emulator's display configuration. Recreate simulators and update IDs if they are removed.

After a localized visual-only change, `CAPTURE_ONLY=02_select_clef ./scripts/capture_store_screenshots.sh ...` can refresh that screen while retaining existing native captures for unchanged screens. This requires a previous complete raw set; the default command captures all six. Never use selective capture to manufacture a complete set when required source captures are missing.

To preview the prepared static website again, run `python3 -m http.server 8780 --bind 127.0.0.1 --directory release/website/frtrev.github.io` from the app checkout and open http://127.0.0.1:8780/sheet-music-rookie/ . The one-time QA server is stopped after preparation.
