#!/usr/bin/env python3
"""Native filesystem validation of verified backups and explicit rotation."""
import importlib.util
import json
import pathlib
import shutil
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
base = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("history_backup", base / "history-backup.py")
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)
scratch = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.gettempdir()).resolve()
scratch.mkdir(parents=True, exist_ok=True)
results = []

def obj(identity="00000001", **values):
    result = dict(protocol="msxchat/1", request_id=identity, conversation_id="00000001",
                  state="pending", message="Pergunta", response_id="", reply="", error_code="")
    result.update(values)
    return result

def put(folder, name, data):
    (folder / name).write_bytes(data if isinstance(data, bytes) else json.dumps(data, ensure_ascii=False).encode())

def record(folder, number=1, state="completed"):
    identity = "%08X" % number
    put(folder, identity + ".ID", identity.encode())
    put(folder, identity + ".REQ", obj(identity))
    if state == "pending":
        return
    if state == "cancelled":
        put(folder, identity + ".CAN", obj(identity, state="cancelled", message=""))
        return
    err = "E_TEST" if state == "error" else ""
    put(folder, identity + ".RSP", obj(identity, state=state, message="", response_id="00000001", reply="Resposta ação", error_code=err))
    put(folder, identity + ".ACK", obj(identity, state="ack", message="", response_id="00000001", error_code=err))

def fails(fn):
    try:
        fn()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile):
        return
    raise AssertionError("Expected rejection")

def check(name, fn):
    directory = pathlib.Path(tempfile.mkdtemp(prefix="msxchat-phase3-", dir=str(scratch))).resolve()
    source = directory / "sd"
    source.mkdir()
    try:
        fn(directory, source)
        results.append({"test": name, "status": "PASS"})
    finally:
        if directory.parent != scratch or not directory.name.startswith("msxchat-phase3-"):
            raise RuntimeError("Unsafe test cleanup")
        shutil.rmtree(directory)

def roundtrip(d, s):
    record(s)
    put(s, "MSXDRAFT.JSN", obj("00000000", state="draft", message="não perder"))
    put(s, "00000002.TMP", b"partial")
    put(s, "00000001.RXT", b"partial network body")
    before = {p.name: p.read_bytes() for p in s.iterdir()}
    app.backup(s, d / "backup.zip")
    assert before == {p.name: p.read_bytes() for p in s.iterdir()}
    app.restore(d / "backup.zip", d / "restored")
    assert before == {p.name: p.read_bytes() for p in (d / "restored").iterdir()}
check("Lossless backup/verify/restore includes UTF8 draft and partial files without modifying source", roundtrip)

def retention(d, s):
    for i in range(1, 5):
        record(s, i)
    record(s, 5, "pending")
    result = app.backup(s, d / "backup.zip", keep=2, rotate=True)
    assert result["rotated_ids"] == ["00000001", "00000002"]
    assert not (s / "00000001.REQ").exists()
    assert (s / "00000001.ID").exists()
    assert (s / "00000002.ID").exists()
    assert (s / "00000003.REQ").exists()
    assert (s / "00000004.REQ").exists()
    assert (s / "00000005.REQ").exists()
    app.restore(d / "backup.zip", d / "restored")
    assert (d / "restored/00000001.RSP").exists()
check("Rotation keeps newest terminal groups and every pending request and ID marker", retention)

def cancelled(d, s):
    record(s, state="cancelled")
    put(s, "00000001.RSP", b"late response left unused")
    app.backup(s, d / "backup.zip", keep=0, rotate=True)
    assert {p.name for p in s.iterdir()} == {"00000001.ID"}
    app.restore(d / "backup.zip", d / "restored")
    assert (d / "restored/00000001.RSP").read_bytes() == b"late response left unused"
check("Cancelled requests and late unused RSP are archived losslessly", cancelled)

def error(d, s):
    record(s, state="error")
    app.backup(s, d / "backup.zip", keep=0, rotate=True)
    assert not (s / "00000001.REQ").exists()
check("Acknowledged remote error can be rotated", error)

def corrupt(d, s):
    record(s)
    put(s, "00000001.ACK", b"broken")
    before = {p.name: p.read_bytes() for p in s.iterdir()}
    fails(lambda: app.backup(s, d / "bad.zip", keep=0, rotate=True))
    assert before == {p.name: p.read_bytes() for p in s.iterdir()}
    app.backup(s, d / "forensic.zip")
    app.verify(d / "forensic.zip")
check("Invalid metadata refuses rotation but allows forensic backup", corrupt)

def mismatch(d, s):
    record(s)
    put(s, "00000001.RSP", obj(state="completed", message="", response_id="12345678", reply="bad"))
    fails(lambda: app.backup(s, d / "backup.zip", keep=0, rotate=True))
    assert (s / "00000001.REQ").exists()
check("ACK/RSP identity mismatch blocks removal", mismatch)

def missing(d, s):
    record(s)
    (s / "00000001.RSP").unlink()
    fails(lambda: app.backup(s, d / "backup.zip", keep=0, rotate=True))
check("Missing acknowledged response blocks rotation", missing)

def conflict(d, s):
    record(s)
    put(s, "00000001.CAN", obj(state="cancelled", message=""))
    fails(lambda: app.backup(s, d / "backup.zip", keep=0, rotate=True))
check("Conflicting cancellation and receipt are rejected", conflict)

def no_marker(d, s):
    record(s)
    (s / "00000001.ID").unlink()
    fails(lambda: app.backup(s, d / "backup.zip", keep=0, rotate=True))
check("Published request without its reservation is rejected", no_marker)

def existing(d, s):
    record(s)
    app.backup(s, d / "backup.zip")
    old = (d / "backup.zip").read_bytes()
    fails(lambda: app.backup(s, d / "backup.zip", keep=0, rotate=True))
    assert (d / "backup.zip").read_bytes() == old
    assert (s / "00000001.REQ").exists()
check("Existing backup is never overwritten or used to authorize removal", existing)

def nonempty(d, s):
    record(s)
    app.backup(s, d / "backup.zip")
    target = d / "restored"
    target.mkdir()
    (target / "keep.txt").write_text("safe")
    fails(lambda: app.restore(d / "backup.zip", target))
    assert list(target.iterdir()) == [target / "keep.txt"]
check("Restore refuses nonempty directories and preserves existing files", nonempty)

def unsafe(d, s):
    with zipfile.ZipFile(d / "bad.zip", "w") as z:
        z.writestr("MANIFEST.json", json.dumps({"format": "msxchat-backup/1", "files": {"../escape": {"bytes": 1, "sha256": "x"}}}))
        z.writestr("DATA/../escape", "x")
    fails(lambda: app.restore(d / "bad.zip", d / "restored"))
    assert not (d / "restored").exists()
check("Archive path traversal refused before any extraction", unsafe)

def checksum(d, s):
    record(s)
    app.backup(s, d / "backup.zip")
    with zipfile.ZipFile(d / "backup.zip") as src, zipfile.ZipFile(d / "bad.zip", "w") as dst:
        for name in src.namelist():
            dst.writestr(name, b"changed" if name.endswith(".REQ") else src.read(name))
    fails(lambda: app.restore(d / "bad.zip", d / "restored"))
    assert not (d / "restored").exists()
check("Changed data with valid ZIP CRC still fails SHA256 verification", checksum)

def pending(d, s):
    record(s, state="pending")
    app.backup(s, d / "backup.zip", keep=0, rotate=True)
    assert (s / "00000001.REQ").exists()
check("Keep zero never removes pending requests", pending)

def interrupted(d, s):
    record(s)
    original = pathlib.Path.unlink
    calls = 0
    def fail_second(path, *args, **kwargs):
        nonlocal calls
        calls += 1
        if calls == 2:
            raise OSError("Simulated media failure")
        return original(path, *args, **kwargs)
    pathlib.Path.unlink = fail_second
    try:
        fails(lambda: app.backup(s, d / "backup.zip", keep=0, rotate=True))
    finally:
        pathlib.Path.unlink = original
    assert (s / "00000001.ID").exists()
    assert not (s / "00000001.REQ").exists()
    app.restore(d / "backup.zip", d / "restored")
    assert (d / "restored/00000001.REQ").exists()
    assert (d / "restored/00000001.RSP").exists()
check("Interrupted rotation removes REQ first and leaves a verified recoverable backup", interrupted)

def unknown(d, s):
    record(s)
    (s / "OTHER.COM").write_bytes(b"unrelated")
    app.backup(s, d / "backup.zip", keep=0, rotate=True)
    assert (s / "OTHER.COM").read_bytes() == b"unrelated"
    assert "OTHER.COM" not in app.verify(d / "backup.zip")["files"]
check("Unrelated files remain untouched", unknown)

(base / "BACKUP-RESULTS.json").write_text(json.dumps({"scope": "Native PC filesystem, ZIP CRC/SHA256 and controlled failure injection", "results": results}, indent=2) + "\n")
print(json.dumps({"passed": len(results), "total": len(results), "scope": "Native PC backup and rotation"}, indent=2))
