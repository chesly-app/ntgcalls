#!/usr/bin/env bash
# iOS port (Chesly fork, 2026-11).
#
# Fallback for a slice that could not be built for real (in practice the simulator, whose
# WebRTC objects are retagged): a framework with the same name, header and exports whose every
# function answers "not built" (gen_stub.py). An app then still links and runs on that slice
# and takes its other path. The release notes say which slices are stubs.
#
# Usage: stub_slice.sh <iphoneos|iphonesimulator> <header> <out dir>
set -euo pipefail

sdk="$1"
header="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
mkdir -p "$3"
out="$(cd "$3" && pwd)"
root="$(cd "$(dirname "$0")/../.." && pwd)"
prop() { sed -n "s/^$1=//p" "$root/version.properties"; }

min_ios="$(prop version.ios_min)"
case "$sdk" in
    iphoneos) triple="arm64-apple-ios${min_ios}" ;;
    iphonesimulator) triple="arm64-apple-ios${min_ios}-simulator" ;;
    *) echo "unknown sdk $sdk" >&2; exit 1 ;;
esac

version="$(sed -n 's/.*project(ntgcalls VERSION \([0-9.]*\).*/\1/p' "$root/CMakeLists.txt")"
full_version="${version}+ios.$(prop version.ios_port).$(git -C "$root" rev-parse --short HEAD).stub"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

python3 -I "$root/ios/scripts/gen_stub.py" "$header" "$work/ntgcalls_stub.c" "$full_version"
sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
# Compiled and linked in two steps, so the object stays for dsymutil until the framework is packaged.
xcrun --sdk "$sdk" clang --target="$triple" -isysroot "$sysroot" -O2 -g -I "$(dirname "$header")" \
    -c "$work/ntgcalls_stub.c" -o "$work/ntgcalls_stub.o"
xcrun --sdk "$sdk" clang --target="$triple" -isysroot "$sysroot" -dynamiclib \
    -install_name @rpath/ntgcalls.framework/ntgcalls \
    -Wl,-exported_symbols_list,"$root/ios/ntgcalls.exp" -Wl,-headerpad_max_install_names \
    -o "$work/libntgcalls.dylib" "$work/ntgcalls_stub.o"
"$root/ios/scripts/package_framework.sh" "$sdk" "$work/libntgcalls.dylib" "$header" "$out/$sdk" "$full_version"
