#!/usr/bin/env python3
"""Verify an unsigned native Gecko Rush IPA against a frozen Android release.

Python standard library only; runs on Linux and macOS without Apple tools.
Checks the actual ZIP, device executable, metadata, PCK checksums and all compiled
scripts. Does not run, sign, build or publish either application.

    python3 .github/verify_mobile.py --ipa GeckoRush-2.3-unsigned.ipa \
        --apk GeckoRush-2.3.apk --apk-sha256 <frozen SHA-256>
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import struct
import sys
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_path(name, label, allow_directory=False):
    require(isinstance(name, str) and name, f"Empty {label}")
    require("\0" not in name and "\\" not in name, f"Unsafe {label}: {name!r}")
    stripped = name[:-1] if allow_directory and name.endswith("/") else name
    parts = stripped.split("/")
    require(stripped and all(part not in ("", ".", "..") for part in parts)
            and ":" not in parts[0], f"Unsafe {label}: {name!r}")
    return stripped


def inspect_archive(archive):
    """Check member names/types first so ZIP lookup never hides a duplicate."""
    members = {}
    for member in archive.infolist():
        original = member.orig_filename
        require(original == member.filename, f"Truncated ZIP name: {original!r}")
        name = safe_path(original, "ZIP path", allow_directory=True)
        require(name not in members, f"Duplicate ZIP path: {name}")
        require(not member.flag_bits & 1, f"Encrypted ZIP member: {name}")
        mode = member.external_attr >> 16
        kind = stat.S_IFMT(mode)
        require(kind in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK),
                f"Unsupported ZIP member type: {name}")
        require(not member.is_dir() or kind in (0, stat.S_IFDIR),
                f"ZIP directory has an incompatible type: {name}")
        require(kind != stat.S_IFDIR or member.is_dir(),
                f"ZIP directory is missing its trailing slash: {name}")
        members[name] = member

    for name in members:
        for parent in PurePosixPath(name).parents:
            if str(parent) == ".":
                continue
            if str(parent) in members:
                require(members[str(parent)].is_dir(),
                        f"ZIP file/symlink also used as a directory: {parent}")

    app_roots = set()
    for name in members:
        parts = name.split("/")
        if len(parts) >= 2 and parts[0] == "Payload":
            require(parts[1].endswith(".app") and parts[1] != ".app",
                    f"Unexpected member directly under Payload: {name}")
            app_roots.add("/".join(parts[:2]))
    require(len(app_roots) == 1,
            f"Expected exactly one Payload/*.app, found {len(app_roots)}")
    root = app_roots.pop()
    if root in members:
        require(members[root].is_dir(), "Payload app root is not a directory")

    # Resolve symlink components before '..', just as a filesystem would. A
    # lexical normpath alone can miss escapes through a second symlink.
    symlinks = {}
    for name, member in members.items():
        if stat.S_IFMT(member.external_attr >> 16) != stat.S_IFLNK:
            continue
        require(name.startswith(root + "/"), f"Symlink outside app: {name}")
        target = archive.read(member).decode("utf-8")
        require(target and not target.startswith("/") and "\0" not in target
                and "\\" not in target, f"Unsafe ZIP symlink target: {name}")
        symlinks[name] = target
    for name, target in symlinks.items():
        stack, pending, followed = name.split("/")[:-1], target.split("/"), 0
        while pending:
            part = pending.pop(0)
            if part in ("", "."):
                continue
            if part == "..":
                require(len(stack) > 2, f"ZIP symlink escapes app: {name}")
                stack.pop()
                continue
            stack.append(part)
            resolved = "/".join(stack)
            if resolved in symlinks:
                followed += 1
                require(followed <= 64, f"ZIP symlink cycle or excessive depth: {name}")
                stack.pop()
                pending = symlinks[resolved].split("/") + pending
    damaged = archive.testzip()
    require(damaged is None, f"ZIP CRC verification failed: {damaged}")
    return members, root


def read_regular(archive, members, name):
    require(name in members, f"Missing IPA member: {name}")
    member = members[name]
    require(not member.is_dir()
            and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG),
            f"Expected a regular file: {name}")
    return archive.read(member)


def version_number(number):
    return f"{number >> 16}.{(number >> 8) & 255}.{number & 255}"


def inspect_macho_slice(data, label):
    require(len(data) >= 32, f"Truncated Mach-O header: {label}")
    require(data[:4] in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"),
            f"Expected a 64-bit Mach-O executable: {label}")
    endian = "<" if data[:4] == b"\xcf\xfa\xed\xfe" else ">"
    _, cpu, subtype, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from(
        endian + "8I", data)
    require(cpu == 0x0100000C, f"Expected arm64, found CPU {cpu:#x}: {label}")
    require(filetype == 2, f"Mach-O is not MH_EXECUTE: {label}")
    require(0 < ncmds <= sizeofcmds // 8 and 32 + sizeofcmds <= len(data),
            f"Invalid Mach-O load-command bounds: {label}")
    cursor, end = 32, 32 + sizeofcmds
    builds = []
    executable_text = False
    for _ in range(ncmds):
        require(cursor + 8 <= end, f"Truncated Mach-O command: {label}")
        command, size = struct.unpack_from(endian + "2I", data, cursor)
        require(size >= 8 and size % 8 == 0 and cursor + size <= end,
                f"Invalid Mach-O command size: {label}")
        if command == 0x32:  # LC_BUILD_VERSION; 2=iOS, 7=iOS simulator.
            require(size >= 24, f"Truncated LC_BUILD_VERSION: {label}")
            platform, minos, sdk, ntools = struct.unpack_from(
                endian + "4I", data, cursor + 8)
            require(size == 24 + 8 * ntools, f"Invalid build tool list: {label}")
            require(platform == 2,
                    f"Mach-O platform is {platform}, expected iOS device (2): {label}")
            require(minos == 0x000E0000,
                    f"Expected minimum iOS 14.0.0, found {version_number(minos)}: {label}")
            require(sdk >= minos, f"Mach-O SDK predates minimum iOS: {label}")
            builds.append({"platform": "iOS device (2)",
                           "minimum_os": version_number(minos),
                           "sdk": version_number(sdk)})
        elif command == 0x19:  # LC_SEGMENT_64
            require(size >= 72, f"Truncated LC_SEGMENT_64: {label}")
            segment = data[cursor + 8:cursor + 24].rstrip(b"\0")
            _, _, fileoff, filesize, _, initprot, nsects, _ = struct.unpack_from(
                endian + "4Q4I", data, cursor + 24)
            require(size == 72 + 80 * nsects,
                    f"Invalid Mach-O segment section list: {label}")
            require(fileoff + filesize <= len(data),
                    f"Mach-O segment lies outside executable: {label}")
            executable_text |= segment == b"__TEXT" and filesize > 0 and bool(initprot & 4)
        elif command == 0x1D:  # LC_CODE_SIGNATURE
            require(size == 16, f"Invalid LC_CODE_SIGNATURE: {label}")
            _, signature_size = struct.unpack_from(endian + "2I", data, cursor + 8)
            require(signature_size == 0, f"Expected an unsigned executable: {label}")
        elif command in (0x24, 0x2F, 0x30):
            raise ValueError(f"Unexpected non-iOS minimum platform command: {label}")
        cursor += size
    require(cursor == end, f"Mach-O load commands do not match sizeofcmds: {label}")
    require(len(builds) == 1, f"Expected one iOS LC_BUILD_VERSION: {label}")
    require(executable_text, f"Mach-O has no executable __TEXT segment: {label}")
    return {"architecture": "arm64", "cpu_subtype": subtype,
            "filetype": "MH_EXECUTE", **builds[0]}


def inspect_macho(data):
    fat_formats = {b"\xca\xfe\xba\xbe": (">", False),
                   b"\xbe\xba\xfe\xca": ("<", False),
                   b"\xca\xfe\xba\xbf": (">", True),
                   b"\xbf\xba\xfe\xca": ("<", True)}
    if data[:4] not in fat_formats:
        return [inspect_macho_slice(data, "main executable")]
    endian, fat64 = fat_formats[data[:4]]
    require(len(data) >= 8, "Truncated universal Mach-O header")
    count = struct.unpack_from(endian + "I", data, 4)[0]
    entry_size = 32 if fat64 else 20
    table_end = 8 + count * entry_size
    require(0 < count <= 16 and table_end <= len(data), "Invalid Mach-O fat slice table")
    slices, ranges = [], []
    for index in range(count):
        values = struct.unpack_from(endian + ("2I2Q2I" if fat64 else "5I"),
                                    data, 8 + index * entry_size)
        cpu, subtype, offset, size, alignment = values[:5]
        require(cpu == 0x0100000C, f"Unexpected architecture in universal Mach-O: {cpu:#x}")
        require(size >= 32 and table_end <= offset and offset + size <= len(data),
                "Universal Mach-O slice lies outside executable")
        require(alignment <= 31 and offset % (1 << alignment) == 0,
                "Invalid universal Mach-O slice alignment")
        require(all(offset + size <= start or stop <= offset for start, stop in ranges),
                "Overlapping universal Mach-O slices")
        ranges.append((offset, offset + size))
        result = inspect_macho_slice(data[offset:offset + size], f"slice {index}")
        require(result["cpu_subtype"] == subtype, "Fat/thin Mach-O CPU subtype mismatch")
        slices.append(result)
    return slices


def inspect_project_version(data, expected, label):
    """Read Godot's ECFG setting rather than accepting an unrelated substring."""
    require(len(data) >= 8 and data[:4] == b"ECFG", f"Invalid project.binary: {label}")
    count = struct.unpack_from("<I", data, 4)[0]
    require(0 < count <= 100000, f"Invalid project setting count: {label}")
    cursor, settings = 8, {}
    for _ in range(count):
        require(cursor + 4 <= len(data), f"Truncated project setting key: {label}")
        key_size = struct.unpack_from("<I", data, cursor)[0]
        cursor += 4
        require(key_size > 0 and cursor + key_size + 4 <= len(data),
                f"Invalid project setting key bounds: {label}")
        key = data[cursor:cursor + key_size].decode("utf-8")
        cursor += key_size
        value_size = struct.unpack_from("<I", data, cursor)[0]
        cursor += 4
        require(cursor + value_size <= len(data), f"Invalid project setting value bounds: {label}")
        require(key not in settings, f"Duplicate project setting {key}: {label}")
        settings[key] = data[cursor:cursor + value_size]
        cursor += value_size
    require(cursor == len(data), f"Unexpected trailing project.binary data: {label}")
    value = settings.get("application/config/version", b"")
    require(len(value) >= 8, f"Missing project version setting: {label}")
    variant, length = struct.unpack_from("<2I", value)
    require(variant == 4 and 8 + length <= len(value), f"Invalid project version string: {label}")
    require(len(value) == 8 + ((length + 3) & ~3), f"Invalid project version padding: {label}")
    actual = value[8:8 + length].decode("utf-8")
    require(actual == expected, f"Expected project version {expected}, found {actual!r}: {label}")
    return actual


def inspect_pck(data, version):
    """Godot 4.6 PCK v3: offsets are relative to this standalone pack."""
    require(len(data) >= 40 and data[:4] == b"GDPC", "Missing Godot GDPC pack header")
    fmt, major, minor, patch, flags, file_base, directory = struct.unpack_from(
        "<5I2Q", data, 4)
    require(fmt == 3, f"Expected Godot PCK v3, found v{fmt}")
    require((major, minor, patch) == (4, 6, 3), "Unexpected PCK Godot engine version")
    require(flags in (0, 2), "PCK is encrypted or has unsupported flags")
    require(40 <= file_base <= directory and directory + 4 <= len(data),
            "PCK data/directory offsets lie outside pack")
    count = struct.unpack_from("<I", data, directory)[0]
    require(0 < count <= 100000, f"Invalid PCK entry count: {count}")
    cursor, entries = directory + 4, {}
    ranges = []
    for _ in range(count):
        require(cursor + 4 <= len(data), "Truncated PCK path length")
        length = struct.unpack_from("<I", data, cursor)[0]
        cursor += 4
        require(length > 0 and cursor + length + 36 <= len(data), "Truncated PCK entry")
        raw_name = data[cursor:cursor + length].rstrip(b"\0")
        name = safe_path(raw_name.decode("utf-8"), "PCK path")
        cursor += length
        offset, size = struct.unpack_from("<2Q", data, cursor)
        md5 = data[cursor + 16:cursor + 32]
        entry_flags = struct.unpack_from("<I", data, cursor + 32)[0]
        cursor += 36
        require(name not in entries, f"Duplicate PCK entry: {name}")
        require(entry_flags == 0, f"Unsupported PCK entry flags: {name}")
        start, stop = file_base + offset, file_base + offset + size
        require(file_base <= start <= stop <= directory,
                f"PCK file overlaps directory or lies outside data: {name}")
        require(all(stop <= other_start or other_stop <= start
                    for other_start, other_stop in ranges), f"Overlapping PCK file: {name}")
        ranges.append((start, stop))
        content = data[start:stop]
        require(hashlib.md5(content).digest() == md5, f"PCK MD5 mismatch: {name}")
        entries[name] = content
    require("project.binary" in entries, "Missing project.binary in game pack")
    inspect_project_version(entries["project.binary"], version, "iOS PCK")
    require(not any(name.startswith(("tests/", "docs/", "scripts/ci/", ".github/"))
                    for name in entries), "Development files included in game pack")
    require(all(name in entries for name in (
        "LICENSE", "assets/fonts/Apache-2.0.txt", "assets/fonts/LICENSE-OpenSans.txt")),
        "Missing code/font license files")
    return entries, {"godot": "4.6.3", "format": fmt, "entries_md5_verified": count,
                     "sha256": hashlib.sha256(data).hexdigest()}


def compare_android(entries, apk_path, expected_sha256, version):
    require(apk_path.is_file(), f"Frozen Android APK not found: {apk_path}")
    digest = sha256_file(apk_path)
    require(digest == expected_sha256, "Android APK SHA-256 differs from the frozen release")
    scripts = {name for name in entries if name.endswith(".gdc")}
    require(len(scripts) == 12, f"Expected 12 compiled scripts, found {len(scripts)}")
    with zipfile.ZipFile(apk_path) as apk:
        names = apk.namelist()
        normalized = set()
        for member in apk.infolist():
            require(member.orig_filename == member.filename,
                    "Truncated ZIP name in Android APK")
            name = safe_path(member.filename, "APK ZIP path", allow_directory=True)
            require(name not in normalized, f"Duplicate APK ZIP path: {name}")
            normalized.add(name)
            require(not member.flag_bits & 1, f"Encrypted APK member: {name}")
            require(stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG, stat.S_IFDIR),
                    f"Unsupported APK ZIP member type: {name}")
        damaged = apk.testzip()
        require(damaged is None, f"Android APK ZIP CRC verification failed: {damaged}")
        inspect_project_version(apk.read("assets/project.binary"), version, "Android APK")
        android_scripts = {name[len("assets/"):] for name in names
                           if name.startswith("assets/") and name.endswith(".gdc")}
        require(scripts == android_scripts, "iOS/Android compiled script path mismatch")
        for name in sorted(scripts):
            require(entries[name].startswith(b"GDSC"), f"Not a compiled GDScript: {name}")
            require(entries[name] == apk.read("assets/" + name),
                    f"iOS/Android compiled script mismatch: {name}")
    return {"apk": str(apk_path), "apk_sha256": digest,
            "compiled_scripts_identical": len(scripts)}


def verify(ipa_path, apk_path, apk_sha256, version="2.3.0", build="5"):
    require(ipa_path.is_file(), f"Actual IPA not found: {ipa_path}")
    with zipfile.ZipFile(ipa_path) as archive:
        members, root = inspect_archive(archive)
        info = plistlib.loads(read_regular(archive, members, root + "/Info.plist"))
        require(isinstance(info, dict), "Info.plist is not a dictionary")
        for key, expected in (("CFBundleIdentifier", "org.geckorush.game"),
                              ("CFBundleShortVersionString", version),
                              ("CFBundleVersion", build), ("CFBundlePackageType", "APPL"),
                              ("MinimumOSVersion", "14.0")):
            require(info.get(key) == expected, f"Unexpected Info.plist {key}: {info.get(key)!r}")
        require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"],
                "Info.plist is not exclusively an iPhoneOS device build")
        require(info.get("DTPlatformName", "iphoneos") == "iphoneos",
                "Info.plist identifies a non-device platform")
        executable_name = info.get("CFBundleExecutable", "")
        safe_path(executable_name, "CFBundleExecutable")
        require("/" not in executable_name, "CFBundleExecutable must be a file name")
        executable_path = root + "/" + executable_name
        executable = read_regular(archive, members, executable_path)
        require(members[executable_path].external_attr >> 16 & 0o111,
                "IPA executable has no Unix execute permission")
        slices = inspect_macho(executable)
        require(not any(name == root + "/_CodeSignature"
                        or name.startswith(root + "/_CodeSignature/")
                        or name == root + "/embedded.mobileprovision" for name in members),
                "IPA unexpectedly includes signing/provisioning resources")
        packs = sorted(name for name, member in members.items()
                       if name.startswith(root + "/") and name.endswith(".pck")
                       and not member.is_dir())
        require(len(packs) == 1, f"Expected one Godot game pack, found {len(packs)}")
        entries, pck = inspect_pck(read_regular(archive, members, packs[0]), version)
        android = compare_android(entries, apk_path, apk_sha256, version)
    return {"result": "PASS", "ipa": str(ipa_path), "ipa_size": ipa_path.stat().st_size,
            "ipa_sha256": sha256_file(ipa_path), "zip_crc": "PASS",
            "app": root, "bundle_identifier": info["CFBundleIdentifier"],
            "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
            "supported_platforms": info["CFBundleSupportedPlatforms"],
            "executable": executable_path, "macho_slices": slices,
            "apple_code_signature": "absent", "pck": {"path": packs[0], **pck},
            "android_comparison": android,
            "runtime_limit": "Static validation only; app was not run or signed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--apk-sha256", required=True, help="SHA-256 of the frozen signed APK")
    parser.add_argument("--version", default="2.3.0")
    parser.add_argument("--build", default="5")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", args.apk_sha256):
        parser.error("--apk-sha256 must contain exactly 64 hexadecimal characters")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", args.version):
        parser.error("--version must be a numeric release version")
    if not re.fullmatch(r"[0-9]+", args.build):
        parser.error("--build must be a numeric build number")
    try:
        report = verify(args.ipa, args.apk, args.apk_sha256.lower(), args.version, args.build)
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile,
            plistlib.InvalidFileException, UnicodeError) as error:
        print(json.dumps({"result": "FAIL", "ipa": str(args.ipa), "error": str(error)}, indent=2))
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
