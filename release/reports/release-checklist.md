# Release checklist

Completed preparation is supported by the linked machine reports and build logs. Signing and owner submission gates remain separate.

## Implementation and configuration
- [x] Inspect actual Flutter/native code, features, dependencies, storage, permissions, artwork, tests and existing website.
- [x] Preserve Android/iOS application identifiers, Apple team and 1.0.0+1 version.
- [x] Preserve working editing, microphone, playback, practice, import/save/share functionality.
- [x] Replace Android debug release-signing fallback with explicit release-key configuration and failure when missing.
- [x] Pin Android target API 36; retain Flutter compile/NDK configuration; enable release shrinking/minification.
- [x] Add adaptive launcher icon using existing artwork.
- [x] Update clear iOS microphone purpose message; retain iOS 15 deployment target and iPhone/iPad families.
- [x] Add app privacy manifest and inspect dependency/Flutter manifests in the archive.
- [x] Replace default iOS launch placeholder using existing app artwork.
- [x] Fix dialog-controller disposal during exit transitions and clef-glyph/label overlap found during capture.
- [x] Keep debug banner disabled and screenshot navigation/sample data outside the production entrypoint.

## Assets, descriptions, and website
- [x] Verify current official screenshot and store graphics specifications; record them in store-requirements.md and scripts/store_targets.json.
- [x] Implement real native capture, deterministic local sample score, six named screens per supported class, and strict PNG validation.
- [x] Generate separate iOS medium/large iPhone and 13-inch iPad groups, plus Android phone/~7-inch/~10-inch groups.
- [x] Generate Google Play 512×512 icon and 1024×500 feature graphic from existing branding.
- [x] Produce ready-to-copy listing fields and automated character-limit report.
- [x] Produce source/dependency privacy audit and owner-reviewed questionnaire recommendations.
- [x] Add website product, privacy, support, screenshot gallery and directory links without changing existing app pages.
- [x] Apply website changes locally; verify all local links and mobile/desktop layout.
- [x] Provide reusable preparation/capture/validation/packaging scripts and setup instructions.

## Executed validation
- [x] Flutter pub get.
- [x] Flutter analyze; full automated suite, including denial/error editing tests (see final-status.md for exact totals).
- [x] Attempt normal Android signed AAB build; separately compile production release code and merge its manifest.
- [x] Build and export signed iOS archive/IPA with the retained signing team.
- [x] Validate IPA signature, distribution profile, identifiers, expiration and embedded privacy resource locally.
- [x] Native UI launch/navigation/staff/score-reopen/tempo/insert controls on all screenshot device classes.
- [x] Validate image format, exact dimensions, alpha, count, PNG CRC, file size and nonblank/unique content; inspect contact sheets.
- [x] Static website link verification and browser checks at mobile/desktop widths.

## Manual submission gates (not completed automatically)
- [ ] Supply the registered Android upload key in ignored android/key.properties and build a signed AAB. No debug-signed substitute is supplied.
- [ ] Confirm 1.0.0 build 1 is unused in each store account; increment if needed and rebuild.
- [ ] Run physical-device microphone allowance/denial/Retry, sung-note quality, audio output, interruptions/backgrounding, and real-file import/export checks on iOS and Android.
- [ ] Supply optional local fixtures for the four explicitly skipped fixture-dependent tests if those external examples need validation.
- [ ] Review artwork/music/SoundFont rights, target audience, category/tags, regional age ratings, privacy/Data Safety and encryption export-compliance answers.
- [ ] Review and publish the website changes; check new URLs over public HTTPS.
- [ ] Validate/upload through App Store Connect and Play Console; select matching screenshot slots; finish account/testing/agreements/pricing/country requirements.

No store submissions, legal declarations, Git commits, pushes or website deployments were performed.
