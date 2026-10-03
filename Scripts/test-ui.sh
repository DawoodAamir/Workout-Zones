#!/bin/bash
set -euo pipefail
platform="${1:-iOS}"
case "$platform" in
  iOS) scheme='Workout Zones'; runtime='iOS-27'; device_platform='iOS Simulator' ;;
  watchOS) scheme='Workout Zones Watch'; runtime='watchOS-27'; device_platform='watchOS Simulator' ;;
  *) echo 'Choose iOS or watchOS.' >&2; exit 2 ;;
esac
mkdir -p build
xcrun simctl list devices available --json > build/simulators.json
simulator_id="${SIMULATOR_UDID:-$(python3 - "$runtime" <<'PY'
import json,sys
from pathlib import Path
for runtime, devices in json.loads(Path('build/simulators.json').read_text())['devices'].items():
    if sys.argv[1] in runtime:
        for device in devices:
            if device.get('isAvailable'):
                print(device['udid']); raise SystemExit
raise SystemExit('Install the requested OS 27 simulator runtime in Xcode.')
PY
)}"
# Boot the paired phone before exercising the companion Watch app.
# Create a dedicated pair so developer-owned simulator pairings stay intact.
if [[ "$platform" == watchOS && -z "${SIMULATOR_UDID:-}" ]]; then
  read -r watch_runtime watch_type phone_runtime phone_type < <(python3 - <<'PAIR'
import json
from pathlib import Path
all_devices = json.loads(Path('build/simulators.json').read_text())['devices']
def select(platform, family):
    for runtime, devices in all_devices.items():
        if f'{platform}-27' in runtime:
            for device in devices:
                if device.get('isAvailable') and device['name'].startswith(family):
                    return runtime, device['deviceTypeIdentifier']
    raise SystemExit(f'Install an OS 27 {family} simulator in Xcode.')
print(*select('watchOS', 'Apple Watch'), *select('iOS', 'iPhone'))
PAIR
)
  simulator_id="$(xcrun simctl create 'Workout Zones workflow Watch' "$watch_type" "$watch_runtime")"
  phone_id="$(xcrun simctl create 'Workout Zones workflow iPhone' "$phone_type" "$phone_runtime")"
  xcrun simctl pair "$simulator_id" "$phone_id"
else
  xcrun simctl list pairs --json > build/pairs.json
  phone_id="$(python3 - "$simulator_id" <<'PAIR'
import json,sys
from pathlib import Path
for pair in json.loads(Path('build/pairs.json').read_text())['pairs'].values():
    if pair['watch']['udid'] == sys.argv[1]:
        print(pair['phone']['udid']); break
PAIR
)"
fi
if [[ "$platform" == watchOS ]]; then
  if [[ -z "$phone_id" ]]; then
    echo 'The selected Watch simulator needs a paired OS 27 iPhone.' >&2
    exit 2
  fi
  xcrun simctl bootstatus "$phone_id" -b
fi
xcrun simctl bootstatus "$simulator_id" -b
result="build/$platform-$(date +%s).xcresult"
capture_evidence() {
  if [[ -d "$result" ]]; then
    xcrun xcresulttool export attachments --path "$result" --output-path "build/Screenshots-$platform" || true
  fi
  xcrun simctl io "$simulator_id" screenshot "build/Simulator-$platform.png" || true
  xcrun simctl spawn "$simulator_id" log show --last 5m --style compact --predicate 'process == "Workout Zones Watch"' > "build/Launch-$platform.log" || true
}
trap capture_evidence EXIT
if [[ "$platform" == watchOS ]]; then
  xcodebuild -project 'Workout Zones.xcodeproj' -scheme "$scheme" -destination "platform=$device_platform,id=$simulator_id" -derivedDataPath build/DerivedData build-for-testing
  xcrun simctl install "$simulator_id" 'build/DerivedData/Build/Products/Debug-watchsimulator/Workout Zones Watch.app'
  xcrun simctl launch "$simulator_id" com.dd.workoutzones.watchkitapp
  xcrun simctl terminate "$simulator_id" com.dd.workoutzones.watchkitapp
fi
xcodebuild -project 'Workout Zones.xcodeproj' -scheme "$scheme" -destination "platform=$device_platform,id=$simulator_id" -derivedDataPath build/DerivedData test -maximum-concurrent-test-simulator-destinations 1 -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath "$result"
