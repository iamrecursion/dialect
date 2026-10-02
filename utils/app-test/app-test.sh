#!/usr/bin/env bash
# Runs the app's tests (DialectTests, hosted by the watch app) in a watch simulator.
#
# Usage: app-test.sh    (SIMULATOR= a name or UDID; by default the Ultra 4)
#
# Two xcodebuild defaults are wrong here. When a test fails it collects diagnostics, and that hangs
# indefinitely (seen with Xcode 27 and watchOS 27), so collection is off. And `-quiet` hides which
# expectation failed, so the full log goes to DerivedData/app-test.log and only the test results,
# errors and the verdict are printed.

set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
simulator="${SIMULATOR:-Apple Watch Ultra 4 (49mm)}"
log="$root/DerivedData/app-test.log"

if [[ $simulator =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    destination="platform=watchOS Simulator,id=$simulator"
else
    destination="platform=watchOS Simulator,name=$simulator"
fi

mkdir -p "$(dirname "$log")"
status=0
xcodebuild test -project "$root/Dialect.xcodeproj" -scheme Dialect -destination "$destination" \
    -derivedDataPath "$root/DerivedData" -collect-test-diagnostics never >"$log" 2>&1 || status=$?

# Swift Testing's results (✔, ✘, and the ↳ details under them), XCTest's (the UI tests), compiler
# and assertion errors, and the verdict.
grep -E "^[✔✘↳]|^Test Case '.*' (passed|failed)|error:|\*\* (TEST|BUILD) " "$log" || true
if [[ $status != 0 ]]; then
    echo "app-test: xcodebuild failed ($status); the full log is $log" >&2
fi
exit "$status"
