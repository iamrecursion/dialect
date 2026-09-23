#!/usr/bin/env bash
# Builds a target of one of Dialect's forks for the watchOS simulator, then proves that the result
# really is a watchOS build.
#
# SwiftPM silently ignores `-Xswiftc -target` and reports success on a macOS build, so a green
# `swift build` says nothing about the platform. This builds through a destination file, which
# SwiftPM does honour, and then checks every object file in its products with `vtool`: if any is
# not WATCHOSSIMULATOR the run fails, however the build itself went.
#
# Usage: fork-watch-build.sh [FORK [TARGET]]    (default: swift-lispkit LispKit)
#
# FORK is a directory under External/. Building LispKit builds the MarkdownKit fork too, since
# LispKit depends on it by path, but it can also be built on its own: `swift-markdownkit MarkdownKit`.

set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
fork="$repo/External/${1:-swift-lispkit}"
target="${2:-LispKit}"

# The package's watchOS floor, as its manifest declares it. The app itself targets watchOS 27.
triple="arm64-apple-watchos10.0-simulator"

# A submodule that is not checked out is an empty directory, which SwiftPM would reject with a far
# less helpful message.
if [[ ! -e "$fork/.git" ]]; then
    echo "fork-watch-build: $fork is not checked out; run \`make submodules\`." >&2
    exit 1
fi

sdk=$(xcrun --sdk watchsimulator --show-sdk-path)
toolchain=$(dirname "$(xcrun --find swiftc)")
destination="$fork/.build/dialect-watchsimulator.json"
mkdir -p "$fork/.build"
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

build=(swift build --package-path "$fork" --destination "$destination" -Xswiftc -D -Xswiftc SPM)
"${build[@]}" --target "$target"

# Swift Build, SwiftPM's default build system, leaves one prelinked object per target directly in
# the products directory: `LispKit.o` for LispKit, and one for each dependency it built.
products="$("${build[@]}" --show-bin-path)"
if [[ ! -f "$products/$target.o" ]]; then
    echo "fork-watch-build: the build left no $target.o in $products to verify." >&2
    exit 1
fi

checked=0
wrong=0
while IFS= read -r -d '' object; do
    checked=$((checked + 1))
    if ! vtool -show-build "$object" | grep -q "platform WATCHOSSIMULATOR"; then
        echo "fork-watch-build: not a watchOS simulator object: $object" >&2
        wrong=$((wrong + 1))
    fi
done < <(find "$products" -maxdepth 1 -name '*.o' -print0)

if ((wrong > 0)); then
    echo "fork-watch-build: $wrong of $checked object files are not for the watchOS simulator." >&2
    exit 1
fi
echo "fork-watch-build: $target.o and all $checked objects are for the watchOS simulator."
