#!/usr/bin/env python3
# iOS port.
#
# Writes a copy of a static archive built for iPhone devices in which every arm64 object says it
# was built for the arm64 iPhone simulator. The code itself is the same arm64 code; the simulator
# runs it as is. This is the arm64-to-sim technique, applied member by member without unpacking,
# because the archive holds members with the same name.
#
# Two kinds of object:
# - LC_BUILD_VERSION (C, C++, ObjC): the platform field changes in place.
# - LC_VERSION_MIN_IPHONEOS (rustc's objects): that command cannot name a simulator, so it is
#   replaced by an LC_BUILD_VERSION, which is 8 bytes longer. If the bytes after the load commands
#   are not free, everything after them moves, and every file offset is updated.
#
# The source may be a universal file holding the archive as its arm64 slice. The output is a plain
# archive, indexed by ranlib, since member sizes can change.
#
# Usage: retag_simulator.py <device.a> <simulator.a>

import os
import struct
import subprocess
import sys

AR_MAGIC = b"!<arch>\n"
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MH_MAGIC_64 = 0xFEEDFACF
MH_OBJECT = 0x1
CPU_TYPE_ARM64 = 0x0100000C
PLATFORM_IOS = 2
PLATFORM_IOSSIMULATOR = 7

LC_SYMTAB = 0x2
LC_DYSYMTAB = 0xB
LC_SEGMENT_64 = 0x19
LC_VERSION_MIN_IPHONEOS = 0x25
LC_BUILD_VERSION = 0x32
# linkedit_data_command: dataoff at 8, datasize at 12.
LINKEDIT_DATA_COMMANDS = {0x1D, 0x1E, 0x26, 0x29, 0x2B, 0x2E}
# Offsets of the (file offset, count) pairs in a dysymtab_command.
DYSYMTAB_OFFSETS = ((32, 36), (40, 44), (48, 52), (56, 60), (64, 68), (72, 76))

HEADER_SIZE = 32
BUILD_VERSION_SIZE = 24
VERSION_MIN_SIZE = 16


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
    """Yields (name, data) for every member of the BSD archive at base."""
    offset = len(AR_MAGIC)
    while offset + 60 <= size:
        f.seek(base + offset)
        header = f.read(60)
        if header[58:60] != b"`\n":
            raise SystemExit(f"bad member header at {offset}")
        name = header[0:16].rstrip(b" ")
        body_size = int(header[48:58].strip())
        data_size = body_size
        if name.startswith(b"#1/"):
            name_len = int(name[3:])
            name = f.read(name_len).rstrip(b"\0")
            data_size -= name_len
        yield name, f.read(data_size)
        offset += 60 + body_size
        offset += offset & 1


def add(buffer, position, delta, form="<I"):
    """Adds delta to the file offset stored at position, if it is set."""
    value = struct.unpack_from(form, buffer, position)[0]
    if value:
        struct.pack_into(form, buffer, position, value + delta)


def load_commands(data):
    """Yields (cmd, position, size) for each load command of a 64-bit Mach-O."""
    ncmds = struct.unpack_from("<I", data, 16)[0]
    position = HEADER_SIZE
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, position)
        yield cmd, position, size
        position += size


def first_data_offset(data):
    """Returns (offset of the first byte after the load commands in use, largest alignment)."""
    first = len(data)
    alignment = 1
    for cmd, position, _ in load_commands(data):
        if cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from("<I", data, position + 64)[0]
            for index in range(nsects):
                section = position + 72 + index * 80
                offset, align, reloff, nreloc = struct.unpack_from("<IIII", data, section + 48)
                if offset:
                    first = min(first, offset)
                    alignment = max(alignment, 1 << align)
                if nreloc:
                    first = min(first, reloff)
        elif cmd == LC_SYMTAB:
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, position + 8)
            if nsyms:
                first = min(first, symoff)
            if strsize:
                first = min(first, stroff)
        elif cmd == LC_DYSYMTAB:
            for offset_at, count_at in DYSYMTAB_OFFSETS:
                if struct.unpack_from("<I", data, position + count_at)[0]:
                    first = min(first, struct.unpack_from("<I", data, position + offset_at)[0])
        elif cmd in LINKEDIT_DATA_COMMANDS:
            dataoff, datasize = struct.unpack_from("<II", data, position + 8)
            if datasize:
                first = min(first, dataoff)
    return first, alignment


def replace_version_min(data):
    """Returns the object with LC_VERSION_MIN_IPHONEOS replaced by a simulator LC_BUILD_VERSION."""
    sizeofcmds = struct.unpack_from("<I", data, 20)[0]
    commands_end = HEADER_SIZE + sizeofcmds
    grown_end = commands_end + BUILD_VERSION_SIZE - VERSION_MIN_SIZE
    first, alignment = first_data_offset(data)
    if first < commands_end:
        raise ValueError("data overlaps the load commands")
    shift = 0
    if grown_end > first:
        shift = -(-(grown_end - first) // alignment) * alignment

    commands = bytearray()
    for cmd, position, size in load_commands(data):
        command = bytearray(data[position:position + size])
        if cmd == LC_VERSION_MIN_IPHONEOS:
            version, sdk = struct.unpack_from("<II", command, 8)
            command = bytearray(struct.pack(
                "<IIIIII", LC_BUILD_VERSION, BUILD_VERSION_SIZE, PLATFORM_IOSSIMULATOR, version, sdk, 0))
        elif shift == 0:
            pass
        elif cmd == LC_SEGMENT_64:
            add(command, 40, shift, "<Q")
            nsects = struct.unpack_from("<I", command, 64)[0]
            for index in range(nsects):
                section = 72 + index * 80
                add(command, section + 48, shift)
                add(command, section + 56, shift)
        elif cmd == LC_SYMTAB:
            add(command, 8, shift)
            add(command, 16, shift)
        elif cmd == LC_DYSYMTAB:
            for offset_at, _ in DYSYMTAB_OFFSETS:
                add(command, offset_at, shift)
        elif cmd in LINKEDIT_DATA_COMMANDS:
            add(command, 8, shift)
        else:
            raise ValueError(f"load command {cmd:#x} is not known to carry no file offset")
        commands += command

    header = bytearray(data[:HEADER_SIZE])
    struct.pack_into("<I", header, 20, len(commands))
    out = bytes(header) + bytes(commands)
    out += b"\0" * (first + shift - len(out))
    return out + data[first:]


def retag(data, counts):
    """Returns the member with its platform changed, or raises ValueError."""
    if len(data) < HEADER_SIZE or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        counts["not_macho"] += 1
        return data
    cputype, _, filetype = struct.unpack_from("<iiI", data, 4)
    if cputype != CPU_TYPE_ARM64 or filetype != MH_OBJECT:
        raise ValueError(f"cputype {cputype:#x}, filetype {filetype}")
    for cmd, position, _ in load_commands(data):
        if cmd == LC_BUILD_VERSION:
            platform = struct.unpack_from("<I", data, position + 8)[0]
            if platform != PLATFORM_IOS:
                raise ValueError(f"platform {platform}")
            patched = bytearray(data)
            struct.pack_into("<I", patched, position + 8, PLATFORM_IOSSIMULATOR)
            counts["build_version"] += 1
            return bytes(patched)
        if cmd == LC_VERSION_MIN_IPHONEOS:
            counts["version_min"] += 1
            return replace_version_min(data)
    counts["no_version"] += 1
    return data


def write_member(out, name, data):
    """Appends a member with its name in front of the data, both ends 8-byte aligned."""
    position = out.tell()
    name_field = len(name) + 1
    name_field += -(position + 60 + name_field) % 8
    padding = -(name_field + len(data)) % 8
    body_size = name_field + len(data) + padding
    header = (
        f"#1/{name_field}".ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6)
        + "100644".ljust(8) + str(body_size).ljust(10) + "`\n"
    )
    out.write(header.encode("ascii"))
    out.write(name + b"\0" * (name_field - len(name)))
    out.write(data)
    out.write(b"\0" * padding)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: retag_simulator.py <device.a> <simulator.a>")
    source, target = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    partial = target + ".partial.a"

    counts = {"build_version": 0, "version_min": 0, "no_version": 0, "not_macho": 0, "symdef": 0}
    failures = []
    with open(source, "rb") as f, open(partial, "wb") as out:
        base, archive_size = arm64_archive(f, source, os.path.getsize(source))
        out.write(AR_MAGIC)
        for name, data in members(f, base, archive_size):
            if name.startswith(b"__.SYMDEF"):
                counts["symdef"] += 1
                continue
            try:
                write_member(out, name, retag(data, counts))
            except ValueError as error:
                failures.append(f"{name.decode('utf-8', 'replace')}: {error}")

    print("retag:", ", ".join(f"{key} {value}" for key, value in counts.items()))
    if failures:
        print(f"retag: {len(failures)} objects not retagged", file=sys.stderr)
        for line in failures[:50]:
            print(f"  {line}", file=sys.stderr)
        os.remove(partial)
        raise SystemExit(1)
    subprocess.run(["xcrun", "ranlib", partial], check=True)
    os.replace(partial, target)


if __name__ == "__main__":
    main()
