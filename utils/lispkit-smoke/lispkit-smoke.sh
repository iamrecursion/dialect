#!/usr/bin/env bash
# Builds the LispKit smoke test and runs it, on this Mac or in a watch simulator.
#
# Usage: lispkit-smoke.sh [mac|watch]    (default: watch)
#
# The watch run builds for the simulator through a destination file, as fork-watch-build.sh does
# (SwiftPM ignores `-Xswiftc -target`), with the keychain entitlements the binary needs there. It
# checks with `vtool` that the binary really is a watchOS one, and spawns it in the simulator named
# by SIMULATOR (a name or UDID; by default the Ultra 4). A simulator this boots is shut down again
# afterwards; one already running is left running.

set -euo pipefail

package=$(cd "$(dirname "$0")" && pwd)
platform="${1:-watch}"
simulator="${SIMULATOR:-Apple Watch Ultra 4 (49mm)}"

# Dependencies are pinned in Package.resolved, which matches the LispKit fork's. They are fetched on
# the first build of a fresh checkout, which needs the network, and not again.
build=(swift build --package-path "$package" --product LispKitSmoke)

case "$platform" in
    mac)
        "${build[@]}"
        exec "$("${build[@]}" --show-bin-path)/LispKitSmoke" </dev/null
        ;;
    watch) ;;
    *)
        echo "lispkit-smoke: unknown platform '$platform'; use mac or watch." >&2
        exit 2
        ;;
esac

# The package's watchOS floor, as its manifest declares it.
triple="arm64-apple-watchos10.0-simulator"
sdk=$(xcrun --sdk watchsimulator --show-sdk-path)
toolchain=$(dirname "$(xcrun --find swiftc)")
destination="$package/.build/dialect-watchsimulator.json"
mkdir -p "$package/.build"
cat >"$destination" <<JSON
{
  "version": 1,
  "sdk": "$sdk",
  "toolchain-bin-dir": "$toolchain",
  "target": "$triple",
  "extra-cc-flags": ["-target", "$triple", "-isysroot", "$sdk"],
  "extra-swiftc-flags": ["-target", "$triple", "-sdk", "$sdk"],
  "extra-cpp-flags": ["-target", "$triple", "-isysroot", "$sdk"]
}
JSON

# The keychain refuses a process with no application identifier. In the simulator, entitlements are
# not read from the code signature but from these two sections, which is how Xcode gives simulator
# builds theirs; the team prefix is never checked there.
entitlements="$package/LispKitSmoke.entitlements"
der="$package/.build/LispKitSmoke.entitlements.der"
derq query -f xml -i "$entitlements" -o "$der" --raw
build+=(
    --destination "$destination"
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$entitlements"
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __ents_der -Xlinker "$der"
)
"${build[@]}"
binary="$("${build[@]}" --show-bin-path)/LispKitSmoke"
if ! vtool -show-build "$binary" | grep -q "platform WATCHOSSIMULATOR"; then
    echo "lispkit-smoke: $binary is not a watchOS simulator binary." >&2
    exit 1
fi

# `simctl list` prints each device as `Name (UDID) (State)`; SIMULATOR may be either.
devices=$(xcrun simctl list devices available)
device=$(grep -F -e "$simulator (" -e "($simulator)" <<<"$devices" | head -1 || true)
if [[ -z "$device" ]]; then
    echo "lispkit-smoke: no available simulator matches '$simulator'." >&2
    exit 1
fi
udid=$(sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' <<<"$device")

if ! grep -q "(Booted)" <<<"$device"; then
    xcrun simctl boot "$udid"
    trap 'xcrun simctl shutdown "$udid"' EXIT
fi
xcrun simctl bootstatus "$udid" >/dev/null

echo "lispkit-smoke: spawning in $device"
xcrun simctl spawn "$udid" "$binary" </dev/null
