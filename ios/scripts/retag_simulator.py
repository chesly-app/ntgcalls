#!/usr/bin/env python3
# iOS port (Chesly fork, 2026-11).
#
# Copies a static archive built for iPhone devices and marks every arm64 object in the copy as
# built for the arm64 iPhone simulator. Only the platform field of each LC_BUILD_VERSION changes,
# in place, so member sizes and the archive's symbol table stay valid. The code itself is the same
# arm64 code; the simulator runs it as is. This is the arm64-to-sim technique, done on the archive
# without unpacking it, because the archive holds members with the same name. The archive may sit
# in a universal file, as an arm64 slice.
#
# Usage: retag_simulator.py <device.a> <simulator.a>
# Fails if any arm64 object carries a platform other than iOS, or an LC_VERSION_MIN_IPHONEOS
# command that cannot be rewritten in place.

import os
import shutil
import struct
import sys

AR_MAGIC = b"!<arch>\n"
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MH_MAGIC_64 = 0xFEEDFACF
MH_OBJECT = 0x1
CPU_TYPE_ARM64 = 0x0100000C
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25
PLATFORM_IOS = 2
PLATFORM_IOSSIMULATOR = 7


def arm64_archive(f, path, file_size):
    """Returns (offset, size) of the arm64 ar archive in a plain archive or a universal file."""
    f.seek(0)
    head = f.read(8)
    if head == AR_MAGIC:
        return 0, file_size
    magic, count = struct.unpack(">II", head)
    if magic not in (FAT_MAGIC, FAT_MAGIC_64):
        raise SystemExit(f"{path} is neither an ar archive nor a universal file: {head.hex()}")
    for _ in range(count):
        if magic == FAT_MAGIC:
            cputype, _, offset, size, _ = struct.unpack(">iiIII", f.read(20))
        else:
            cputype, _, offset, size, _, _ = struct.unpack(">iiQQII", f.read(32))
        if cputype == CPU_TYPE_ARM64:
            f.seek(offset)
            if f.read(len(AR_MAGIC)) != AR_MAGIC:
                raise SystemExit(f"the arm64 slice of {path} is not an ar archive")
            return offset, size
    raise SystemExit(f"{path} has no arm64 slice")


def members(f, base, size):
    """Yields (data_offset, data_size, name) for every member of the BSD archive at base."""
    offset = len(AR_MAGIC)
    while offset + 60 <= size:
        f.seek(base + offset)
        header = f.read(60)
        if header[58:60] != b"`\n":
            raise SystemExit(f"bad member header at {offset}")
        name = header[0:16].rstrip(b" ")
        body_size = int(header[48:58].strip())
        data = base + offset + 60
        data_size = body_size
        if name.startswith(b"#1/"):
            name_len = int(name[3:])
            name = f.read(name_len).rstrip(b"\0")
            data += name_len
            data_size -= name_len
        yield data, data_size, name.decode("utf-8", "replace")
        offset += 60 + body_size
        offset += offset & 1


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: retag_simulator.py <device.a> <simulator.a>")
    source, target = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    partial = target + ".partial"
    shutil.copyfile(source, partial)

    counts = {"retagged": 0, "already_simulator": 0, "no_version": 0, "not_macho": 0, "symdef": 0}
    failures = []
    size = os.path.getsize(partial)
    with open(partial, "r+b") as f:
        base, archive_size = arm64_archive(f, source, size)
        for data, data_size, name in list(members(f, base, archive_size)):
            if name.startswith("__.SYMDEF"):
                counts["symdef"] += 1
                continue
            f.seek(data)
            head = f.read(32)
            if len(head) < 32 or struct.unpack_from("<I", head, 0)[0] != MH_MAGIC_64:
                counts["not_macho"] += 1
                continue
            _, cputype, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IiiIIIII", head, 0)
            if cputype != CPU_TYPE_ARM64 or filetype != MH_OBJECT:
                failures.append(f"{name}: cputype {cputype:#x} filetype {filetype}")
                continue
            commands = f.read(sizeofcmds)
            cursor = 0
            tagged = False
            for _ in range(ncmds):
                cmd, cmdsize = struct.unpack_from("<II", commands, cursor)
                if cmd == LC_BUILD_VERSION:
                    platform = struct.unpack_from("<I", commands, cursor + 8)[0]
                    if platform == PLATFORM_IOS:
                        f.seek(data + 32 + cursor + 8)
                        f.write(struct.pack("<I", PLATFORM_IOSSIMULATOR))
                        counts["retagged"] += 1
                    elif platform == PLATFORM_IOSSIMULATOR:
                        counts["already_simulator"] += 1
                    else:
                        failures.append(f"{name}: platform {platform}")
                    tagged = True
                elif cmd == LC_VERSION_MIN_IPHONEOS:
                    failures.append(f"{name}: LC_VERSION_MIN_IPHONEOS cannot be rewritten in place")
                    tagged = True
                cursor += cmdsize
            if not tagged:
                counts["no_version"] += 1

    print("retag:", ", ".join(f"{key} {value}" for key, value in counts.items()))
    if failures:
        print(f"retag: {len(failures)} objects not retagged", file=sys.stderr)
        for line in failures[:50]:
            print(f"  {line}", file=sys.stderr)
        os.remove(partial)
        raise SystemExit(1)
    os.replace(partial, target)


if __name__ == "__main__":
    main()
