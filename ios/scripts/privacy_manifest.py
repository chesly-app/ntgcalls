#!/usr/bin/env python3
# iOS port (Chesly fork, 2026-11).
#
# Writes the framework's PrivacyInfo.xcprivacy from the symbols the binary imports (nm -u -j).
# Apple's required-reason APIs are matched by symbol. A category is declared only with a reason
# that has been checked against this library; a category found without one stops the build, so
# a person picks the reason instead of the script guessing it.
#
# Usage: privacy_manifest.py <undefined symbols file> <output .xcprivacy>

import plistlib
import sys

# Category -> (symbols that use it, reason codes this library may declare, or None if unchecked).
CATEGORIES = {
    # WebRTC and the engine measure elapsed time; nothing leaves the device.
    "NSPrivacyAccessedAPICategorySystemBootTime": (
        {"_mach_absolute_time", "_mach_continuous_time", "_mach_approximate_time"},
        ["35F9.1"],
    ),
    # stat-family calls on files the app itself opens, inside its own container.
    "NSPrivacyAccessedAPICategoryFileTimestamp": (
        {
            "_stat", "_fstat", "_lstat", "_fstatat",
            "_stat$INODE64", "_fstat$INODE64", "_lstat$INODE64", "_fstatat$INODE64",
            "_getattrlist", "_fgetattrlist", "_getattrlistat", "_getattrlistbulk",
        },
        ["C617.1"],
    ),
    "NSPrivacyAccessedAPICategoryDiskSpace": (
        {
            "_statfs", "_fstatfs", "_statvfs", "_fstatvfs",
            "_statfs$INODE64", "_fstatfs$INODE64",
        },
        None,
    ),
    "NSPrivacyAccessedAPICategoryUserDefaults": (
        {
            "_OBJC_CLASS_$_NSUserDefaults",
            "_CFPreferencesCopyAppValue", "_CFPreferencesSetAppValue",
            "_CFPreferencesCopyValue", "_CFPreferencesSetValue",
        },
        None,
    ),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": (
        {"_OBJC_CLASS_$_UITextInputMode"},
        None,
    ),
}


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: privacy_manifest.py <undefined symbols file> <output>")
    with open(sys.argv[1], encoding="utf-8") as f:
        imported = {line.strip() for line in f if line.strip()}

    accessed = []
    unchecked = []
    for category, (symbols, reasons) in CATEGORIES.items():
        used = sorted(imported & symbols)
        if not used:
            continue
        print(f"{category}: {', '.join(used)}")
        if reasons is None:
            unchecked.append(category)
            continue
        accessed.append({
            "NSPrivacyAccessedAPIType": category,
            "NSPrivacyAccessedAPITypeReasons": reasons,
        })
    if unchecked:
        raise SystemExit(f"no checked reason for: {', '.join(unchecked)}; add one in {__file__}")

    manifest = {
        "NSPrivacyTracking": False,
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [],
        "NSPrivacyAccessedAPITypes": accessed,
    }
    with open(sys.argv[2], "wb") as f:
        plistlib.dump(manifest, f)


if __name__ == "__main__":
    main()
