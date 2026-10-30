#!/usr/bin/env python3
"""Offline backup and explicit rotation for the MSXCHAT 8.3 journal. No network."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import zipfile

NAME = re.compile(r"(?:0000[0-9A-F]{4}\.(?:ID|REQ|RSP|ACK|CAN|TMP|NEW|AKT|CNT|RXT)|MSXDRAFT\.(?:JSN|BAK|TMP))\Z")
KEYS = {"protocol", "request_id", "conversation_id", "state", "message", "response_id", "reply", "error_code"}

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()

def pairs(items):
    obj = {}
    for key, value in items:
        if key in obj:
            raise ValueError("Duplicate JSON key")
        obj[key] = value
    return obj

def envelope(path, identity, state=None):
    raw = path.read_bytes()
    if len(raw) > 32767 or raw.startswith(b"\xef\xbb\xbf"):
        raise ValueError("Invalid JSON size/BOM: " + path.name)
    obj = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs)
    if not isinstance(obj, dict) or set(obj) != KEYS or any(not isinstance(v, str) for v in obj.values()):
        raise ValueError("Invalid flat envelope: " + path.name)
    for value in obj.values():
        if any(0xD800 <= ord(ch) <= 0xDFFF for ch in value):
            raise ValueError("Unpaired surrogate")
    if obj["protocol"] != "msxchat/1" or obj["conversation_id"] != "00000001" or obj["request_id"] != identity:
        raise ValueError("Envelope identity mismatch: " + path.name)
    if state and obj["state"] != state:
        raise ValueError("Unexpected state: " + path.name)
    if len(obj["message"]) > 2047 or len(obj["reply"]) > 2047:
        raise ValueError("Message too large")
    if len(obj["error_code"]) > 31 or any(ord(c) < 32 or ord(c) > 126 for c in obj["error_code"]):
        raise ValueError("Invalid error_code")
    return obj

def empty(obj, *fields):
    if any(obj[f] for f in fields):
        raise ValueError("Nonempty field in terminal record")

def terminal_groups(source, names):
    result = []
    for name in sorted(names):
        if not name.endswith(".REQ"):
            continue
        identity = name[:8]
        if identity == "00000000" or identity + ".ID" not in names:
            raise ValueError("Missing reservation: " + identity)
        req = envelope(source / name, identity, "pending")
        if not req["message"]:
            raise ValueError("Empty request")
        empty(req, "response_id", "reply", "error_code")
        ackname, canname, rspname = (identity + ext for ext in (".ACK", ".CAN", ".RSP"))
        if ackname in names and canname in names:
            raise ValueError("Both ACK and CAN: " + identity)
        group = [name]
        if canname in names:
            can = envelope(source / canname, identity, "cancelled")
            empty(can, "message", "response_id", "reply", "error_code")
            group.append(canname)
            if rspname in names:
                group.append(rspname)  # late, unused response preserved byte-for-byte
        elif ackname in names:
            ack = envelope(source / ackname, identity, "ack")
            empty(ack, "message", "reply")
            if rspname not in names:
                raise ValueError("Missing RSP: " + identity)
            rsp = envelope(source / rspname, identity)
            empty(rsp, "message")
            rid = rsp["response_id"]
            if not re.fullmatch(r"[0-9A-F]{8}", rid) or rid == "00000000":
                raise ValueError("Invalid response ID")
            if rsp["state"] == "completed":
                if not rsp["reply"] or rsp["error_code"]:
                    raise ValueError("Invalid completed response")
            elif rsp["state"] == "error":
                if not rsp["error_code"]:
                    raise ValueError("Missing remote error")
            else:
                raise ValueError("Invalid response state")
            if ack["response_id"] != rid or ack["error_code"] != rsp["error_code"]:
                raise ValueError("ACK/RSP mismatch")
            group.extend([rspname, ackname])
        else:
            continue  # pending requests are never rotated
        result.append((identity, group))
    return result

def verify(archive):
    with zipfile.ZipFile(archive) as z:
        entries = z.namelist()
        if len(entries) != len(set(entries)) or z.testzip() is not None:
            raise ValueError("Duplicate ZIP entry or CRC failure")
        manifest = json.loads(z.read("MANIFEST.json"), object_pairs_hook=pairs)
        if manifest.get("format") != "msxchat-backup/1" or not isinstance(manifest.get("files"), dict):
            raise ValueError("Unknown backup format")
        files = manifest["files"]
        if set(entries) != {"MANIFEST.json"} | {"DATA/" + n for n in files}:
            raise ValueError("Unexpected ZIP contents")
        for name, meta in files.items():
            if not NAME.fullmatch(name):
                raise ValueError("Unsafe filename in archive")
            h = hashlib.sha256()
            size = 0
            with z.open("DATA/" + name) as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    h.update(chunk)
                    size += len(chunk)
            if size != meta["bytes"] or h.hexdigest() != meta["sha256"]:
                raise ValueError("Backup checksum mismatch: " + name)
        return manifest

def backup(source, destination, keep=20, rotate=False):
    source, destination = pathlib.Path(source).resolve(), pathlib.Path(destination).resolve()
    if not source.is_dir() or keep < 0:
        raise ValueError("Invalid directory or retention")
    names = {}
    for p in source.iterdir():
        if NAME.fullmatch(p.name):
            if p.is_symlink() or not p.is_file():
                raise ValueError("Nonregular source: " + p.name)
            names[p.name] = {"bytes": p.stat().st_size, "sha256": digest(p)}
    if not names:
        raise ValueError("No MSXCHAT files")
    groups = terminal_groups(source, names) if rotate else []
    rotate_groups = groups[:-keep] if keep else groups
    manifest = {"format": "msxchat-backup/1", "files": names,
                "rotation_ids": [i for i, group in rotate_groups], "keep": keep}
    # Exclusive creation: an existing backup is never replaced.
    with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("MANIFEST.json", json.dumps(manifest, sort_keys=True))
        for name in sorted(names):
            z.write(source / name, "DATA/" + name)
    with destination.open("r+b") as committed:
        os.fsync(committed.fileno())
    verify(destination)
    removed = []
    if rotate:
        # Recheck every candidate before the first removal. One publisher / offline media.
        candidates = [name for identity, group in rotate_groups for name in group]
        for name in candidates:
            p = source / name
            if p.is_symlink() or digest(p) != names[name]["sha256"]:
                raise ValueError("Source changed; no rotation performed: " + name)
        for identity, group in rotate_groups:
            # REQ first: interrupted cleanup cannot revive an old pending request.
            # ID remains permanently reserved. All removed bytes are in verified ZIP.
            for name in group:
                (source / name).unlink()
                removed.append(name)
    return {"backed_up": len(names), "rotated_ids": [i for i, group in rotate_groups],
            "removed_files": removed, "archive": str(destination)}

def restore(archive, destination):
    manifest = verify(archive)  # validate whole archive before creating target files
    destination = pathlib.Path(destination)
    if destination.is_symlink():
        raise ValueError("Symlink target refused")
    destination = destination.resolve()
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise ValueError("Restore requires a new or empty directory")
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for name in sorted(manifest["files"]):
            with z.open("DATA/" + name) as src, (destination / name).open("xb") as target:
                for chunk in iter(lambda: src.read(65536), b""):
                    target.write(chunk)
                target.flush()
                os.fsync(target.fileno())
    for name, meta in manifest["files"].items():
        if digest(destination / name) != meta["sha256"]:
            raise ValueError("Restored checksum mismatch: " + name)
    return {"restored": len(manifest["files"]), "directory": str(destination)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    b = commands.add_parser("backup")
    b.add_argument("source")
    b.add_argument("archive")
    b.add_argument("--rotate", action="store_true", help="Remove older terminal records only after backup verification; keep all ID markers")
    b.add_argument("--keep", type=int, default=20, help="Terminal requests to retain on MSX (default 20)")
    v = commands.add_parser("verify")
    v.add_argument("archive")
    r = commands.add_parser("restore")
    r.add_argument("archive")
    r.add_argument("destination")
    args = parser.parse_args()
    try:
        if args.command == "backup":
            result = backup(args.source, args.archive, args.keep, args.rotate)
        elif args.command == "restore":
            result = restore(args.archive, args.destination)
        else:
            result = {"verified_files": len(verify(args.archive)["files"])}
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as err:
        parser.exit(1, "ERROR: " + str(err) + "\n")

if __name__ == "__main__":
    main()
