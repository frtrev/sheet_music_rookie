# Final release preparation status — 6 November 2026

> Identifier update: source now uses `com.neotheone.sheetmusicrookie` on iOS and Android. Existing release packages and verification reports below retain the previous identifier and must be regenerated before upload. Register/select the new identifier in the store accounts and obtain matching iOS provisioning. Changing the identifier installs a separate app; export any sheets needed from older test installations before switching.

> Subsequent source update: the app now has inline lyric editing, a remembered tapped-note speaker toggle, measure repeat/volta controls, the Sheets manager, and Spanish language support. The binaries/screenshots and results below describe the earlier release snapshot; regenerate the release package for the updated app.

The release package is prepared locally. **Android submission remains blocked by the missing registered upload key.** Physical audio/permission checks, owner declarations, website publication and portal submission remain manual gates. No upload, store questionnaire submission, Git commit/push or website deployment was performed.

## Delivered

- Signed iOS `release/ios/Runner.xcarchive` and App Store export `release/ios/sheet_music_rookie.ipa`. Existing bundle identifier and signing team preserved; version 1.0.0 build 1. Local codesign, App Store distribution-profile, debugger-entitlement, profile-expiration, identifier and privacy-resource checks pass. See ios-package-verification.json for the exact IPA hash. App Store Connect validation/upload was not performed.
- 36 native app screenshots: six each for medium iPhone (1206×2622), large iPhone (1320×2868), 13-inch iPad (2064×2752), Android phone (1080×1920), ~7-inch tablet (1200×1920), and ~10-inch tablet (1600×2560). **All 36 screenshots plus the two Google graphics pass the final 38/38 technical checks. No manual resizing is required for the configured store slots.** No image is resized, stretched or cropped; only alpha is flattened into RGB at the same resolution.
- Existing-brand Google Play icon (512×512 RGBA PNG) and feature graphic (1024×500 opaque RGB PNG), validated automatically and visually inspected.
- Separate ready-to-copy Apple/Google metadata, privacy/Data Safety/age-rating recommendations, privacy audit, current official store-requirement notes, website changes, screenshot CSV/JSON reports, visual QA contact sheets, and the release checklist.
- Website changes applied locally to `/Users/franciscotrevino/Documents/Git/frtrev.github.io`: new product/privacy/support pages, icon, three-image gallery and root directory links. Existing app pages and shared styling preserved. Eight changed/new files are packaged in release/website/changes with a checksum manifest and text patch. All 244 local links across 20 HTML files pass; mobile and desktop browser checks pass.
- Reusable `scripts/prepare_store_release.sh` and supporting capture/validation/metadata/website/package verification tools. Dedicated capture devices and setup commands documented in release/README.md and capture-devices.env.

## Executed checks

| Check | Result |
|---|---|
| flutter pub get | Passed; locked runtime versions retained |
| flutter analyze | Passed, no issues |
| flutter test | 147 passed, 4 optional fixture tests skipped |
| Normal Android release AAB build | Attempted; fails explicitly without release signing properties |
| Final Android production release compile + manifest merge | Passed; min SDK 24, target 36, debuggable=false, microphone plus app-internal receiver permission, no Internet permission |
| iOS archive and App Store export | Passed; Xcode 27.0, iOS SDK 27.0, deployment target 15.0 |
| IPA signature/profile verification | Passed; distribution profile expires 30 July 2027 UTC |
| Native integration UI runs | Passed for all six capture classes; chooser refreshes verify the final spacing fix |
| Screenshot/graphic validation | 38/38 passed; dimensions, format/alpha, count, size, PNG structure/CRC, uniqueness and nonblank checks |
| Metadata length limits | Passed |
| Website links + responsive browser QA | Passed locally; live HTTPS not checked because publication was not authorized |
| Bash/Python syntax; git diff whitespace | Passed |

The checks were executed as individual phases while implementing and repairing issues. The full orchestration command was syntax checked and its constituent steps exercised; it was not redundantly rerun end to end after all individual phases completed. run-status.tsv consolidates actual results. Recovered failed attempts are described in recovered-attempts.md and were not counted as successful captures/builds.

Four skipped tests require optional external fixtures: GENERALUSER_EXAMPLE, LYRIC_EXAMPLE, MUSESCORE_EXAMPLE and REPEAT_EXAMPLE. Built-in synthetic/core tests for the relevant subsystems ran; no optional fixture success is claimed.

## Changes required by validation

Android release signing now fails closed instead of using the debug key; target API is pinned to 36, release shrinking/minification is enabled, and adaptive artwork is present. iOS has the clearer microphone purpose string, copied app privacy manifest, and real launch artwork replacing the default placeholder. Save/tempo dialogs retain controllers through route exit animations. Clef glyph metrics no longer overlap the label. Existing application behavior and identifiers are preserved.

## Owner actions before submission

1. Configure the app's registered Android upload key in ignored android/key.properties, then build and verify a signed AAB. No keystore was created, overwritten, exposed or substituted with a debug key.
2. Confirm 1.0.0 build 1 is unused in both portals. If not, increment the version/build and regenerate binaries/verification reports.
3. On physical iOS and Android devices, check real microphone allowance/denial/Retry, singing accuracy, playback output, background/audio interruptions and imports/exports across restart. Synthetic denial/error tests and native editor/navigation checks passed; physical/acoustic validation was not performed.
4. Review content/artwork/SoundFont rights, age ratings/target audience, Data Safety/App Privacy, export compliance and store account/testing requirements. Recommendations are not automatically submitted declarations.
5. Review and publish the website changes, then verify the marketing/privacy/support URLs over public HTTPS before entering them in the portals.
6. Validate and upload the signed packages in App Store Connect/Google Play, selecting the screenshot slots documented in release/README.md.

Gradle reports existing legacy Kotlin plugin migration warnings from record_android/package_info_plus; current builds/compile checks pass. No runtime dependency upgrade was forced as part of this preparation.
