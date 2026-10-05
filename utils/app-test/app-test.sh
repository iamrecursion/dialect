#!/usr/bin/env bash
# Runs the app's tests in a watch simulator: the unit tests (DialectTests, hosted by the watch app),
# the smoke tests (DialectUITests/SmokeUITests), or the rest of the UI tests.
#
# Usage: app-test.sh unit|smoke|ui    (SIMULATOR= a name or UDID; by default the Ultra 4)
#
# The UI tests run on UI_WORKERS clones of the simulator at once (4 by default), which xcodebuild
# hands a test class at a time.
#
# Two xcodebuild defaults don't suit. Collecting diagnostics after a failure hangs on Xcode 27 and
# watchOS 27, so it's off. `-quiet` hides which expectation failed, so the full log goes to
# DerivedData/app-test-<mode>.log and only the results, errors and verdict are printed.

set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
simulator="${SIMULATOR:-Apple Watch Ultra 4 (49mm)}"
mode="${1:-}"

case "$mode" in
    unit) selection=(-only-testing:DialectTests) ;;
    smoke) selection=(-only-testing:DialectUITests/SmokeUITests) ;;
    ui)
        selection=(
            -only-testing:DialectUITests -skip-testing:DialectUITests/SmokeUITests
            -parallel-testing-enabled YES -parallel-testing-worker-count "${UI_WORKERS:-4}"
        )
        ;;
    *)
        echo "usage: app-test.sh unit|smoke|ui" >&2
        exit 2
        ;;
esac
log="$root/DerivedData/app-test-$mode.log"

if [[ $simulator =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    destination="platform=watchOS Simulator,id=$simulator"
else
    destination="platform=watchOS Simulator,name=$simulator"
fi

mkdir -p "$(dirname "$log")"
status=0
xcodebuild test -project "$root/Dialect.xcodeproj" -scheme Dialect -destination "$destination" \
    -derivedDataPath "$root/DerivedData" -collect-test-diagnostics never "${selection[@]}" \
    >"$log" 2>&1 || status=$?

# Swift Testing's results (✔, ✘, and the ↳ details under them), XCTest's (the UI tests), compiler
# and assertion errors, and the verdict.
grep -E "^[✔✘↳]|^Test Case '.*' (passed|failed)|error:|\*\* (TEST|BUILD) " "$log" || true
if [[ $status != 0 ]]; then
    echo "app-test: xcodebuild failed ($status); the full log is $log" >&2
fi
exit "$status"
