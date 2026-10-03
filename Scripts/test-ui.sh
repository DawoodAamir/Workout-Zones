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
xcrun simctl bootstatus "$simulator_id" -b
result="build/$platform-$(date +%s).xcresult"
xcodebuild -project 'Workout Zones.xcodeproj' -scheme "$scheme" -destination "platform=$device_platform,id=$simulator_id" -derivedDataPath build/DerivedData test -maximum-concurrent-test-simulator-destinations 1 -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath "$result"
xcrun xcresulttool export attachments --path "$result" --output-path "build/Screenshots-$platform"
