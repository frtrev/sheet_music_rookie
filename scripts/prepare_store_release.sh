#!/bin/bash
# Runs independent phases to completion and reports every failure. Never publishes.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/{reports,android,ios}
status=release/reports/run-status.tsv
printf 'step\tstatus\texit_code\n' > "$status"
failures=0
run() {
  local name="$1"; shift
  echo "Running $name"
  "$@" > "release/reports/$name.log" 2>&1
  local code=$?
  if [[ $code -eq 0 ]]; then
    printf '%s\tPASS\t0\n' "$name" >> "$status"
  else
    printf '%s\tFAIL\t%s\n' "$name" "$code" >> "$status"
    echo "$name failed ($code); see release/reports/$name.log"
    failures=$((failures+1))
  fi
}
run pub-get flutter pub get
run analyze flutter analyze
run tests flutter test
run launch-artwork env CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smr-clang-cache" swift scripts/generate_launch_images.swift
run android-release flutter build appbundle --release
if [[ -f build/app/outputs/bundle/release/app-release.aab ]] && grep -q $'android-release\tPASS' "$status"; then
  cp build/app/outputs/bundle/release/app-release.aab release/android/
fi
run ios-release flutter build ipa --release
if grep -q $'ios-release\tPASS' "$status"; then
  run ios-package python3 scripts/verify_ios_package.py
fi
if grep -q $'ios-release\tPASS' "$status" && grep -q $'ios-package\tPASS' "$status"; then
  [[ ! -d build/ios/archive/Runner.xcarchive ]] || ditto build/ios/archive/Runner.xcarchive release/ios/Runner.xcarchive
  for ipa in build/ios/ipa/*.ipa; do [[ ! -f "$ipa" ]] || cp "$ipa" release/ios/; done
fi
run graphics env CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smr-clang-cache" swift scripts/store_images.swift
run metadata python3 scripts/generate_store_metadata.py
run dependencies python3 scripts/audit_dependencies.py
# Device IDs are explicit to avoid running on a user's personal device.
for pair in 'iphone_other_required:IOS_MEDIUM_DEVICE' 'iphone_large:IOS_LARGE_DEVICE' 'ipad:IOS_IPAD_DEVICE' 'phone:ANDROID_CAPTURE_DEVICE' 'tablet_7:ANDROID_CAPTURE_DEVICE' 'tablet_10:ANDROID_CAPTURE_DEVICE'; do
  group="${pair%%:*}"; variable="${pair#*:}"; device="${!variable:-}"
  if [[ -n "$device" ]]; then
    run "screenshots-$group" ./scripts/capture_store_screenshots.sh "$group" "$device"
  else
    printf 'capture-%s\tBLOCKED_DEVICE_NOT_SET\t1\n' "$group" >> "$status"
    failures=$((failures+1))
  fi
done
run assets python3 scripts/validate_store_assets.py
run native-artifacts python3 scripts/verify_native_artifacts.py
run contact-sheets env CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smr-clang-cache" swift scripts/make_contact_sheets.swift
if [[ -d "${WEBSITE_SOURCE:-../frtrev.github.io}" ]]; then
  run website python3 scripts/prepare_release_website.py --source "${WEBSITE_SOURCE:-../frtrev.github.io}"
  run website-links python3 scripts/check_website_links.py release/website/frtrev.github.io
  run website-package python3 scripts/package_website_changes.py --source "${WEBSITE_SOURCE:-../frtrev.github.io}"
else
  printf 'website\tBLOCKED_SOURCE_NOT_FOUND\t1\n' >> "$status"; failures=$((failures+1))
fi
mkdir -p release/store_assets release/store_metadata
rsync -a --exclude raw store_assets/ release/store_assets/
rsync -a store_assets/metadata/ release/store_metadata/
cp store_assets/validation/*.json store_assets/validation/*.csv release/reports/ 2>/dev/null || true
python3 scripts/summarize_release.py
printf '\nFailures or blocked steps: %s\n' "$failures"
echo 'See release/README.md and release/reports/run-status.tsv. No upload, push or publication was performed.'
[[ $failures -eq 0 ]]
