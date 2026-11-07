#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
group="${1:?Usage: capture_store_screenshots.sh GROUP DEVICE_ID}"
device="${2:?Device identifier required}"
python3 -c 'import json,sys; assert sys.argv[1] in json.load(open("scripts/store_targets.json"))["groups"]' "$group"
mkdir -p release/reports "store_assets/raw/$group"
endpoint=http://127.0.0.1:8765
if [[ "$group" == iphone* || "$group" == ipad ]]; then
  simulator_name=$(xcrun simctl list devices available -j | python3 -c 'import json,sys;d=sys.argv[1];print(next((x["name"] for xs in json.load(sys.stdin)["devices"].values() for x in xs if x["udid"]==d),""))' "$device")
  if [[ "$simulator_name" != 'SMR Store '* ]]; then echo 'Use a dedicated simulator named SMR Store ...' >&2; exit 1; fi
  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b
  xcrun simctl ui "$device" appearance light
  xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
else
  if [[ "$device" != emulator-* ]]; then echo 'Use a dedicated emulator, not a personal device.' >&2; exit 1; fi
  adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
  avd_name=$("$adb" -s "$device" emu avd name | head -n 1 | tr -d '\r')
  if [[ "$avd_name" != smr_phone ]]; then echo 'Use the dedicated smr_phone AVD.' >&2; exit 1; fi
  read -r width height density < <(python3 -c 'import json,sys;g=json.load(open("scripts/store_targets.json"))["groups"][sys.argv[1]]; print(*g["size"], {"phone":360,"tablet_7":320,"tablet_10":300}[sys.argv[1]])' "$group")
  "$adb" -s "$device" shell wm size "${width}x${height}"
  "$adb" -s "$device" shell wm density "$density"
  "$adb" -s "$device" shell settings put system accelerometer_rotation 0
  "$adb" -s "$device" shell settings put system user_rotation 0
  "$adb" -s "$device" shell cmd uimode night no
  "$adb" -s "$device" shell settings put global sysui_demo_allowed 1
  "$adb" -s "$device" shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null
  "$adb" -s "$device" shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
  "$adb" -s "$device" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null
  "$adb" -s "$device" shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null
  "$adb" -s "$device" shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null
  endpoint=http://10.0.2.2:8765
fi
python3 scripts/native_capture_server.py --group "$group" --device "$device" > "release/reports/native-$group.log" 2>&1 &
bridge_pid=$!
trap 'kill "$bridge_pid" 2>/dev/null || true' EXIT
python3 - "$group" "$device" "$bridge_pid" <<'PYREADY'
import json,os,sys,time,urllib.request
for attempt in range(30):
    try:
        os.kill(int(sys.argv[3]),0)
        with urllib.request.urlopen('http://127.0.0.1:8765/health',timeout=1) as response: result=json.load(response)
        assert result=={'group':sys.argv[1],'device':sys.argv[2]}, 'Capture bridge belongs to a different run'
        break
    except Exception:
        if attempt==29:raise
        time.sleep(.1)
PYREADY
flutter drive --driver=test_driver/store_screenshots.dart --target=integration_test/store_screenshots_test.dart --dart-define="CAPTURE_SERVER=$endpoint" --dart-define="CAPTURE_ONLY=${CAPTURE_ONLY:-}" -d "$device" > "release/reports/capture-$group.log" 2>&1
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smr-clang-cache" swift scripts/store_images.swift normalize "$group" "store_assets/raw/$group"
python3 scripts/validate_store_assets.py --group "$group"
