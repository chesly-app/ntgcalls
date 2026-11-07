#!/usr/bin/env bash
# iOS port.
#
# Gate G0 on one packaged slice. Every check prints PASS or FAIL with what it saw, and the
# script fails if any check failed. The output is the slice's part of the build report.
#
#  1 arm64 only                      7 no ObjC class or category in the binary
#  2 platform and minimum iOS <= 17  8 no AVAudioSession or AVFoundation import
#  3 install name                    9 dSYM present, UUIDs equal, DWARF inside
#  4 only system libraries linked   10 no debug map (N_OSO) in the shipped binary
#  5 only _ntg_* exported           11 header identical to the release header
#  6 no defined weak external       12 version string, Info.plist, privacy manifest
#                                   13 software video factories linked, OpenH264 not
#                                   14 no import of the system libc++'s std::__1
#
# Usage: check_slice.sh <iphoneos|iphonesimulator> <slice dir>
set -uo pipefail

sdk="$1"
slice="$(cd "$2" && pwd)"
root="$(cd "$(dirname "$0")/../.." && pwd)"
fw="$slice/ntgcalls.framework"
bin="$fw/ntgcalls"
dsym="$slice/ntgcalls.framework.dSYM"
failed=0

pass() { echo "PASS $1: $2"; }
fail() { echo "FAIL $1: $2"; failed=1; }
check() { if [ "$2" = ok ]; then pass "$1" "$3"; else fail "$1" "$3"; fi; }

if [ ! -f "$bin" ]; then
    echo "FAIL binary: $bin is missing"
    exit 1
fi

# 1
archs="$(lipo -archs "$bin")"
check "arch" "$([ "$archs" = arm64 ] && echo ok)" "$archs"

# 2
platforms="$("$root/ios/scripts/platforms.sh" "$bin")"
check "platform" "$([ "$platforms" = "$sdk" ] && echo ok)" "$platforms"
minos="$(otool -l "$bin" | awk '$1 == "cmd" && $2 == "LC_BUILD_VERSION" {w = 1; next} w && $1 == "minos" {print $2; exit}')"
major="${minos%%.*}"
check "minimum iOS" "$([ -n "$major" ] && [ "$major" -le 17 ] && echo ok)" "minos ${minos:-none}, limit 17"

# 3
install_name="$(otool -D "$bin" | tail -n +2)"
check "install name" "$([ "$install_name" = "@rpath/ntgcalls.framework/ntgcalls" ] && echo ok)" "$install_name"

# 4
dylibs="$(otool -l "$bin" | awk '$1 == "cmd" && ($2 == "LC_LOAD_DYLIB" || $2 == "LC_LOAD_WEAK_DYLIB" || $2 == "LC_REEXPORT_DYLIB" || $2 == "LC_LAZY_LOAD_DYLIB") {w = 1; next} w && $1 == "name" {print $2; w = 0}')"
outside="$(echo "$dylibs" | grep -v -E '^(/System/Library/Frameworks/|/usr/lib/)' || true)"
banned="$(echo "$dylibs" | grep -E '/(AppKit|OpenGL|ScreenCaptureKit|AVFoundation|AVFAudio|AudioToolbox|CoreAudio|UIKit)\.framework/' || true)"
check "linked libraries" "$([ -z "$outside" ] && [ -z "$banned" ] && echo ok)" "$(echo "$dylibs" | sed 's|.*/||' | paste -sd ' ' -)${outside:+; not a system library: $outside}${banned:+; not allowed: $banned}"

# 5
exports="$(nm -gU -j "$bin")"
export_count="$(echo "$exports" | grep -c . || true)"
foreign="$(echo "$exports" | grep -v '^_ntg_' || true)"
check "exports" "$([ -z "$foreign" ] && [ "$export_count" -gt 0 ] && echo ok)" "$export_count symbols${foreign:+; not _ntg_*: $(echo "$foreign" | head -20 | paste -sd ' ' -)}"

# 6
weak="$(nm -m "$bin" | grep -v '(undefined)' | grep ' weak external ' || true)"
check "weak definitions" "$([ -z "$weak" ] && echo ok)" "$(echo "$weak" | grep -c . || true) defined weak external${weak:+: $(echo "$weak" | head -10 | awk '{print $NF}' | paste -sd ' ' -)}"

# 7
objc_sections="$(otool -l "$bin" | awk '$1 == "sectname" && $2 ~ /^__objc_(classlist|nlclslist|catlist|nlcatlist|catlist2)$/ {print $2}' | sort -u | paste -sd ' ' -)"
check "ObjC classes" "$([ -z "$objc_sections" ] && echo ok)" "${objc_sections:-no class or category list}"

# 8
av="$(nm -u -j "$bin" | grep -E 'AVAudioSession|_OBJC_CLASS_\$_AV|_AudioUnit|_AudioComponent|_AudioSession' || true)"
check "audio imports" "$([ -z "$av" ] && echo ok)" "${av:+$(echo "$av" | head -10 | paste -sd ' ' -)}${av:-none}"

# 9
bin_uuid="$(dwarfdump --uuid "$bin" | awk '{print $2}')"
dsym_uuid="$(dwarfdump --uuid "$dsym" 2>/dev/null | awk '{print $2}')"
dwarf="$dsym/Contents/Resources/DWARF/ntgcalls"
info_size="$(otool -l "$dwarf" 2>/dev/null | awk '$1 == "sectname" && $2 == "__debug_info" {w = 1; next} w && $1 == "size" {print $2; exit}')"
info_bytes="$((${info_size:-0}))"
check "dSYM" "$([ -n "$bin_uuid" ] && [ "$bin_uuid" = "$dsym_uuid" ] && [ "$info_bytes" -gt 0 ] && echo ok)" "binary $bin_uuid, dSYM ${dsym_uuid:-missing}, __debug_info $info_bytes bytes"

# 10
oso="$(nm -ap "$bin" | grep -c ' OSO ' || true)"
check "debug map" "$([ "$oso" -eq 0 ] && echo ok)" "$oso N_OSO entries"

# 11
expected_header="$(awk '$2 == "ntgcalls.h" {print $1}' "$root/ios/pins.sha256")"
actual_header="$(shasum -a 256 "$fw/Headers/ntgcalls.h" | awk '{print $1}')"
check "header" "$([ "$expected_header" = "$actual_header" ] && echo ok)" "sha256 $actual_header"
if [ "$expected_header" != "$actual_header" ] && [ -n "${RELEASE_HEADER:-}" ] && [ -f "$RELEASE_HEADER" ]; then
    diff -u "$RELEASE_HEADER" "$fw/Headers/ntgcalls.h" | head -60
fi

# 12
version="$(cat "$slice/VERSION")"
# No -q: grep leaving early would kill strings, and pipefail would read that as no match.
check "version string" "$(strings -a "$bin" | grep -Fx "$version" >/dev/null && echo ok)" "$version"
check "Info.plist" "$(plutil -lint -s "$fw/Info.plist" >/dev/null && echo ok)" "$(plutil -extract CFBundleShortVersionString raw "$fw/Info.plist" 2>/dev/null) ($(plutil -extract CFBundleVersion raw "$fw/Info.plist" 2>/dev/null)), $(plutil -extract NTGCallsVersion raw "$fw/Info.plist" 2>/dev/null)"
reasons="$(plutil -convert json -o - "$fw/PrivacyInfo.xcprivacy" 2>/dev/null | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(t["NSPrivacyAccessedAPIType"].replace("NSPrivacyAccessedAPICategory","")+"="+",".join(t["NSPrivacyAccessedAPITypeReasons"]) for t in d["NSPrivacyAccessedAPITypes"]) or "none")' 2>/dev/null)"
check "privacy manifest" "$([ -n "$reasons" ] && echo ok)" "${reasons:-unreadable}"

# 13: read from the dSYM's symbol table, since the shipped binary keeps only its exports.
if [[ "$version" != *.stub ]]; then
    symbols="$(nm "$dwarf" 2>/dev/null)"
    missing=""
    for name in CreateVp8Encoder VP9Decoder CreateLibaomAv1Encoder CreateDav1dDecoder; do
        echo "$symbols" | grep "$name" >/dev/null || missing="$missing $name"
    done
    h264="$(echo "$symbols" | grep -c -E 'WelsCreate|openh264' || true)"
    check "video factories" "$([ -z "$missing" ] && [ "$h264" -eq 0 ] && echo ok)" "missing:${missing:- none}; OpenH264 symbols: $h264"
fi

# 14: all C++ inside the framework uses the archive's libc++ (std::__Cr). An import naming
# std::__1 means something was compiled against the SDK's headers and exchanges std:: objects
# with the archive's code across two libc++ builds. Matched anywhere in a name: the namespace can
# sit in the middle of one (std::runtime_error(std::__1::string const&)). libc++.1.dylib may still
# be linked for the C++ runtime (operator new, __cxa_*), which names no std::__1 type.
sdk_libcxx="$(nm -u -j "$bin" | grep 'St3__1' || true)"
check "libc++ namespace" "$([ -z "$sdk_libcxx" ] && echo ok)" "$(echo "$sdk_libcxx" | grep -c . || true) std::__1 imports${sdk_libcxx:+: $(echo "$sdk_libcxx" | head -10 | paste -sd ' ' -)}"

size="$(stat -f %z "$bin")"
echo "INFO size: $size bytes ($((size / 1048576)) MiB) stripped binary"
echo "INFO exported: $(echo "$exports" | head -3 | paste -sd ' ' -) ..."

exit "$failed"
