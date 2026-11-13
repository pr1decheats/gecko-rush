"""Reconstruct a frozen release from checked repository parts, without signing."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def assemble(manifest_path, output):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if output.name != manifest["filename"]:
        raise ValueError("Output filename differs from frozen manifest")
    parts = manifest["parts"]
    if not isinstance(parts, list) or not 1 <= len(parts) <= 16:
        raise ValueError("Invalid release part list")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    digest, total, seen = hashlib.sha256(), 0, set()
    try:
        with temporary.open("wb") as destination:
            for part in parts:
                name, size, expected = part["file"], part["size"], part["sha256"]
                if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.bin", name) or name in seen:
                    raise ValueError("Unsafe or duplicate release part")
                if type(size) is not int or not 0 < size < 19 * 1024 * 1024:
                    raise ValueError("Invalid part size")
                if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
                    raise ValueError("Invalid part digest")
                seen.add(name)
                path = manifest_path.parent / name
                if path.is_symlink() or path.stat().st_size != size:
                    raise ValueError("Part file size/type differs")
                block = path.read_bytes()
                if hashlib.sha256(block).hexdigest() != expected:
                    raise ValueError("Part SHA-256 differs")
                destination.write(block)
                digest.update(block)
                total += len(block)
        if total != manifest["size"] or digest.hexdigest() != manifest["sha256"]:
            raise ValueError("Assembled release size/SHA-256 differs")
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"FROZEN_RELEASE_PASS {output.name} {total} {digest.hexdigest()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    assemble(args.manifest, args.output)
