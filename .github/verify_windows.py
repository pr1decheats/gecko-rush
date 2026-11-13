#!/usr/bin/env python3
"""Read-only Windows PE/PCK release verification; Python standard library only.

Keep beside verify_mobile.py, whose validated PCK/ECFG/APK checks are reused.
This checks package contents and metadata; it does not execute Windows code.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

from verify_mobile import compare_android, inspect_pck, require, sha256_file


def inspect_pe(data):
    require(len(data) >= 64 and data[:2] == b"MZ", "Missing DOS executable header")
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    require(64 <= pe and pe + 24 <= len(data), "PE header is outside executable")
    require(data[pe:pe + 4] == b"PE\0\0", "Missing PE signature")
    machine, count, _, _, _, optional_size, characteristics = struct.unpack_from("<HHIIIHH", data, pe + 4)
    require(machine == 0x8664, "Expected Windows AMD64 executable")
    require(1 <= count <= 96 and characteristics & 2, "Invalid PE executable section header")
    optional = pe + 24
    require(optional_size >= 240 and optional + optional_size + count * 40 <= len(data), "Truncated PE optional/section header")
    require(struct.unpack_from("<H", data, optional)[0] == 0x20b, "Expected PE32+ 64-bit optional header")
    require(struct.unpack_from("<H", data, optional + 68)[0] == 2, "Expected Windows GUI subsystem")
    require(struct.unpack_from("<I", data, optional + 108)[0] >= 16, "Missing PE data directories")
    entry = struct.unpack_from("<I", data, optional + 16)[0]
    sections = []
    for index in range(count):
        offset = optional + optional_size + index * 40
        name = data[offset:offset + 8].rstrip(b"\0").decode("ascii")
        virtual_size, rva, raw_size, raw = struct.unpack_from("<4I", data, offset + 8)
        flags = struct.unpack_from("<I", data, offset + 36)[0]
        require(raw_size == 0 or raw >= optional + optional_size + count * 40, "PE raw section overlaps headers")
        require(raw + raw_size <= len(data), f"PE section is outside executable: {name}")
        sections.append({"name": name, "rva": rva, "virtual_size": virtual_size,
                         "raw": raw, "raw_size": raw_size, "flags": flags})
    require(any(s["rva"] <= entry < s["rva"] + s["virtual_size"] and s["flags"] & 0x20000000 for s in sections), "PE entry point is not in executable code")

    def file_offset(rva, size):
        for section in sections:
            delta = rva - section["rva"]
            if 0 <= delta and delta + size <= section["raw_size"]:
                return section["raw"] + delta
        raise ValueError("PE resource RVA is outside section data")

    resource_rva, resource_size = struct.unpack_from("<2I", data, optional + 112 + 2 * 8)
    require(resource_rva and resource_size >= 16, "Missing Windows resources")
    resource = file_offset(resource_rva, resource_size)

    def resource_entries(relative):
        require(0 <= relative and relative + 16 <= resource_size, "PE resource directory is outside resources")
        named, numbered = struct.unpack_from("<2H", data, resource + relative + 12)
        count = named + numbered
        require(count <= 4096 and relative + 16 + count * 8 <= resource_size, "Invalid PE resource directory entries")
        return [struct.unpack_from("<2I", data, resource + relative + 16 + i * 8) for i in range(count)]

    roots = resource_entries(0)
    require(any(name == 14 and target & 0x80000000 for name, target in roots), "Missing application icon group resource")
    versions = [target & 0x7fffffff for name, target in roots if name == 16 and target & 0x80000000]
    require(len(versions) == 1, "Expected one Windows VERSIONINFO resource")
    leaves = []

    def visit(relative, depth=0):
        require(depth <= 4, "Windows resource tree is too deep")
        for _, target in resource_entries(relative):
            if target & 0x80000000:
                visit(target & 0x7fffffff, depth + 1)
            else:
                require(target + 16 <= resource_size, "PE version resource leaf is outside resources")
                rva, size, _, _ = struct.unpack_from("<4I", data, resource + target)
                require(size >= 52, "Truncated Windows VERSIONINFO")
                offset = file_offset(rva, size)
                leaves.append(data[offset:offset + size])
    visit(versions[0])
    require(leaves, "Missing Windows version resource data")
    metadata = [inspect_version_info(leaf) for leaf in leaves]
    require(all(item == metadata[0] for item in metadata), "Windows version resources disagree between languages")
    certificate_offset, certificate_size = struct.unpack_from("<2I", data, optional + 112 + 4 * 8)
    return {"machine": "AMD64", "optional_header": "PE32+", "subsystem": "Windows GUI",
            "icon_group_present": True, "signed": bool(certificate_offset and certificate_size),
            "metadata": metadata[0], "sections": sections}


def inspect_version_info(data):
    strings = {}
    fixed = {}

    def align(value):
        return (value + 3) & ~3

    def block(offset, limit, depth=0):
        require(depth <= 8 and offset + 6 <= limit, "Truncated Windows version block")
        length, value_length, kind = struct.unpack_from("<3H", data, offset)
        end = offset + length
        require(length >= 6 and end <= limit, "Invalid Windows version block length")
        cursor = offset + 6
        key_start = cursor
        while cursor + 2 <= end and data[cursor:cursor + 2] != b"\0\0":
            cursor += 2
        require(cursor + 2 <= end, "Unterminated Windows version key")
        key = data[key_start:cursor].decode("utf-16le")
        cursor = align(cursor + 2)
        value_size = value_length * 2 if kind == 1 else value_length
        require(cursor + value_size <= end, "Windows version value exceeds block")
        value = data[cursor:cursor + value_size]
        if key == "VS_VERSION_INFO":
            require(value_size == 52, "Missing VS_FIXEDFILEINFO")
            fields = struct.unpack("<13I", value)
            require(fields[0] == 0xfeef04bd, "Invalid VS_FIXEDFILEINFO signature")
            fixed["file_version"] = ".".join(str(n) for n in (fields[2] >> 16, fields[2] & 65535, fields[3] >> 16, fields[3] & 65535))
            fixed["product_version"] = ".".join(str(n) for n in (fields[4] >> 16, fields[4] & 65535, fields[5] >> 16, fields[5] & 65535))
        elif kind == 1 and value_size:
            text = value.decode("utf-16le").rstrip("\0")
            require(key not in strings or strings[key] == text, "Conflicting Windows version string")
            strings[key] = text
        cursor = align(cursor + value_size)
        while cursor + 6 <= end:
            child_length = struct.unpack_from("<H", data, cursor)[0]
            if child_length == 0:
                break
            cursor = align(block(cursor, end, depth + 1))
        return end

    block(0, len(data))
    require(fixed, "Missing Windows fixed version metadata")
    return {**fixed, "strings": strings}


def verify(exe_path, apk_path, apk_sha256, version="2.5.0", file_version="2.5.0.7", product_version="2.5.0.0", product_name="Gecko Rush"):
    data = exe_path.read_bytes()
    pe = inspect_pe(data)
    require(data[-4:] == b"GDPC" and len(data) >= 12, "Missing embedded PCK footer")
    pack_size = struct.unpack_from("<Q", data, len(data) - 12)[0]
    pack_start = len(data) - 12 - pack_size
    require(0 <= pack_start and pack_start + 40 <= len(data) - 12, "Embedded PCK is outside executable")
    for section in pe["sections"]:
        if section["raw_size"] and section["raw"] + section["raw_size"] > pack_start:
            require(section["name"] == "pck" and section["raw"] == pack_start
                    and section["raw_size"] == pack_size + 12,
                    "Embedded PCK overlaps unrelated PE section data")
    entries, pck = inspect_pck(data[pack_start:-12], version)
    android = compare_android(entries, apk_path, apk_sha256, version)
    metadata = pe["metadata"]
    require(metadata["file_version"] == file_version, f"Expected PE file version {file_version}, found {metadata['file_version']}")
    require(metadata["product_version"] == product_version, f"Expected PE product version {product_version}, found {metadata['product_version']}")
    require(metadata["strings"].get("ProductName") == product_name, "PE ProductName does not name the game")
    require(metadata["strings"].get("FileDescription") in
            (product_name, f"{product_name} {version}", f"{product_name} {version.rsplit('.', 1)[0]}"),
            "PE FileDescription does not name this game/version")
    require(metadata["strings"].get("FileVersion") == file_version, "PE FileVersion string differs from fixed metadata")
    require(metadata["strings"].get("ProductVersion") == product_version, "PE ProductVersion string differs from fixed metadata")
    return {"result": "PASS", "exe": str(exe_path), "exe_size": len(data),
            "exe_sha256": hashlib.sha256(data).hexdigest(), "project_version": version,
            "pe": {key: value for key, value in pe.items() if key != "sections"},
            "pck": {**pck, "embedded_offset": pack_start, "embedded_size": pack_size},
            "android": android,
            "runtime_limit": "Static package check; execute this exact EXE on Windows for launch validation."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, type=Path)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--version", default="2.5.0")
    parser.add_argument("--file-version", default="2.5.0.7")
    parser.add_argument("--product-version", default="2.5.0.0")
    parser.add_argument("--product-name", default="Gecko Rush")
    args = parser.parse_args()
    try:
        report = verify(args.exe, args.apk, args.apk_sha256.lower(), args.version, args.file_version, args.product_version, args.product_name)
    except (ValueError, OSError, UnicodeError, struct.error) as error:
        print(json.dumps({"result": "FAIL", "error": str(error)}, indent=2), file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
