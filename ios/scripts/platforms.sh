#!/usr/bin/env bash
# iOS port (Chesly fork, 2026-11).
# Prints the distinct platforms of the Mach-O objects in a file or archive, one word each:
# iphoneos, iphonesimulator, or the raw platform value for anything else.
# Usage: platforms.sh <file>
set -euo pipefail
otool -l "$1" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { want = 1; next }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" { print "version_min_iphoneos"; next }
    want && $1 == "platform" {
        p = $2
        if (p == "2" || p == "IOS") p = "iphoneos"
        else if (p == "7" || p == "IOSSIMULATOR") p = "iphonesimulator"
        print p
        want = 0
    }
' | sort -u | paste -sd ' ' -
