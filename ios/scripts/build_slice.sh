#!/usr/bin/env bash
# iOS port.
#
# Builds the C library for one iOS slice and packages it (package_framework.sh) as
#   <out>/<sdk>/ntgcalls.framework
#   <out>/<sdk>/ntgcalls.framework.dSYM
#
# Usage: build_slice.sh <iphoneos|iphonesimulator> <deps dir> <out dir>
set -euo pipefail

sdk="$1"
deps="$(cd "$2" && pwd)"
mkdir -p "$3"
out="$(cd "$3" && pwd)"
root="$(cd "$(dirname "$0")/../.." && pwd)"
prop() { sed -n "s/^$1=//p" "$root/version.properties"; }

case "$sdk" in
    iphoneos) simulator=OFF ;;
    iphonesimulator) simulator=ON ;;
    *) echo "unknown sdk $sdk" >&2; exit 1 ;;
esac

build="$root/build/$sdk"

echo "::group::Configure ${sdk}"
rm -rf "$build" "$root/shared-output"
cmake -S "$root" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DSTATIC_BUILD=OFF \
    -DBINDING=c \
    -DPython_EXECUTABLE="$(command -v python3)" \
    -DCMAKE_TOOLCHAIN_FILE="$root/cmake/Toolchain.cmake" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DNTG_IOS_SIMULATOR="$simulator" \
    -DNTG_IOS_DEPS="$deps/$sdk"
echo "::endgroup::"

echo "::group::Build ${sdk}"
cmake --build "$build" -j"$(sysctl -n hw.ncpu)"
echo "::endgroup::"

dylib="$root/shared-output/lib/libntgcalls.dylib"
header="$root/shared-output/include/ntgcalls.h"
test -f "$dylib"
test -f "$header"

# The device slice links the downloaded archive itself; only the simulator links the retagged copy.
if [ "$sdk" = iphoneos ]; then
    grep -q 'deps/libwebrtc/src/lib/libwebrtc.a' "$build/build.ninja"
    if grep -q 'lib/simulator/libwebrtc.a' "$build/build.ninja"; then
        echo "the device slice links the retagged archive" >&2
        exit 1
    fi
else
    grep -q 'deps/libwebrtc/src/lib/simulator/libwebrtc.a' "$build/build.ninja"
fi

version="$(sed -n 's/.*project(ntgcalls VERSION \([0-9.]*\).*/\1/p' "$root/CMakeLists.txt")"
full_version="${version}+ios.$(prop version.ios_port).$(git -C "$root" rev-parse --short HEAD)"
"$root/ios/scripts/package_framework.sh" "$sdk" "$dylib" "$header" "$out/$sdk" "$full_version"
