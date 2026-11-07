#!/usr/bin/env bash
# iOS port (Chesly fork, 2026-11).
#
# Packages a built libntgcalls.dylib as one slice of the framework:
#   <slice>/ntgcalls.framework       the stripped library at @rpath/ntgcalls.framework/ntgcalls,
#                                    the C header unchanged, a module map for module `ntgcalls`,
#                                    Info.plist, PrivacyInfo.xcprivacy, and the licence notices
#                                    with a pointer to the corresponding source
#   <slice>/ntgcalls.framework.dSYM  the debug info, for xcodebuild -create-xcframework -debug-symbols
#   <slice>/VERSION                  the string ntg_get_version() returns
#
# Usage: package_framework.sh <iphoneos|iphonesimulator> <dylib> <header> <slice dir> <full version>
set -euo pipefail

sdk="$1"
dylib="$2"
header="$3"
slice="$4"
full_version="$5"
root="$(cd "$(dirname "$0")/../.." && pwd)"
prop() { sed -n "s/^$1=//p" "$root/version.properties"; }

case "$sdk" in
    iphoneos) platform_name=iPhoneOS ;;
    iphonesimulator) platform_name=iPhoneSimulator ;;
    *) echo "unknown sdk $sdk" >&2; exit 1 ;;
esac

short_version="${full_version%%+*}"
fw="$slice/ntgcalls.framework"
rm -rf "$slice"
mkdir -p "$fw/Headers" "$fw/Modules"

cp "$dylib" "$fw/ntgcalls"
install_name_tool -id @rpath/ntgcalls.framework/ntgcalls "$fw/ntgcalls"
dsymutil "$fw/ntgcalls" -o "$slice/ntgcalls.framework.dSYM"
# Debug info lives in the dSYM. The shipped binary keeps its exported C symbols and no debug map,
# so no path of the machine that built it.
strip -S -x "$fw/ntgcalls"
codesign --remove-signature "$fw/ntgcalls" 2>/dev/null || true

cp "$header" "$fw/Headers/ntgcalls.h"
cat > "$fw/Modules/module.modulemap" <<'MODULEMAP'
framework module ntgcalls {
    header "ntgcalls.h"
    export *
}
MODULEMAP

sed -e "s|@SHORT_VERSION@|${short_version}|" \
    -e "s|@BUNDLE_VERSION@|$(prop version.ios_port)|" \
    -e "s|@FULL_VERSION@|${full_version}|" \
    -e "s|@PLATFORM@|${platform_name}|" \
    -e "s|@MIN_IOS@|$(prop version.ios_min)|" \
    "$root/ios/Info.plist.in" > "$fw/Info.plist"
plutil -convert binary1 "$fw/Info.plist"

nm -u -j "$fw/ntgcalls" > "$slice/undefined.txt"
python3 -I "$root/ios/scripts/privacy_manifest.py" "$slice/undefined.txt" "$fw/PrivacyInfo.xcprivacy"

cp "$root/LICENSE" "$fw/LICENSE"
cp "$root/THIRD_PARTY_NOTICES.md" "$fw/THIRD_PARTY_NOTICES.md"
{
    echo "ntgcalls ${full_version} for iOS (${sdk}, arm64)"
    echo "LGPL-3.0. A modified version of https://github.com/pytgcalls/ntgcalls; IOS_PORT.md in"
    echo "the source below lists the changes and how to rebuild this framework."
    echo "Corresponding source: https://github.com/${GITHUB_REPOSITORY:-chesly-app/ntgcalls}/tree/$(git -C "$root" rev-parse HEAD)"
} > "$fw/SOURCE.txt"

echo "$full_version" > "$slice/VERSION"
