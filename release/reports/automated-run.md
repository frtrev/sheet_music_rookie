# Automated release preparation report

Generated 2026-11-06T17:46:29-06:00.

| Step | Status | Exit |
|---|---|---|
| pub-get | PASS | 0 |
| analyze | PASS | 0 |
| tests-147-passed-4-optional-skips | PASS_WITH_SKIPS | 0 |
| android-release | BLOCKED_MISSING_UPLOAD_KEY | 1 |
| android-release-production-compile | PASS | 0 |
| ios-release-archive-and-app-store-export | PASS | 0 |
| ios-package-signature-profile-verification | PASS | 0 |
| capture-iphone_other_required | PASS | 0 |
| capture-iphone_large | PASS | 0 |
| capture-ipad | PASS | 0 |
| capture-phone | PASS | 0 |
| capture-tablet_7 | PASS | 0 |
| capture-tablet_10 | PASS | 0 |
| assets-38-checks | PASS | 0 |
| metadata-length-checks | PASS | 0 |
| privacy-dependency-artifact-audit | PASS | 0 |
| website-244-local-links | PASS | 0 |
| website-browser-responsive-checks | PASS | 0 |
| website-local-application | PASS | 0 |
| shell-python-syntax-and-git-diff-check | PASS | 0 |
| physical-microphone-audio-interruption-tests | MANUAL_REQUIRED | 1 |
| website-production-publication | OWNER_APPROVAL_REQUIRED | 1 |
| store-questionnaires-and-upload | OWNER_ACTION_REQUIRED | 1 |

## Asset and package checks

- Image validation: PASS; 38/38 checks passed.
- Website links: PASS; 244 links across 20 HTML files.
- IPA local signature/profile verification: PASS; SHA-256 `92d53ca88bf289d020c1a03f92aaeb4d04bf913308ac0123f9c0f2970217e1ae`. Confirm this hash matches the exported binary from the current successful build.

Technical image validation must be combined with successful native capture and visual review. Missing or failed build steps are not satisfied by an artifact from a previous run. Read release/README.md and the owner submission checklist before uploading. No publishing is performed.
