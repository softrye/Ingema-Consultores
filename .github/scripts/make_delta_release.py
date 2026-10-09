#!/usr/bin/env python3
"""Create an InGe+ DELTA ZIP with changed files, deletion records and preimage SHA256."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
from zipfile import ZipFile, ZIP_DEFLATED
from datetime import datetime, timezone


def git(*args):
    return subprocess.check_output(["git", *args])


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_at(rev, name):
    proc = subprocess.Popen(["git", "show", f"{rev}:{name}"], stdout=subprocess.PIPE)
    h = hashlib.sha256()
    with proc.stdout:
        for chunk in iter(lambda: proc.stdout.read(1024 * 1024), b""):
            h.update(chunk)
    if proc.wait() != 0:
        raise RuntimeError(f"Failed to read base content: {name}")
    return h.hexdigest()


def check_name(name):
    parts = name.split("/")
    p = PurePosixPath(name)
    if not name or p.is_absolute() or any(x in ("", ".", "..") for x in parts) or ":" in name or "\\" in name:
        raise ValueError(f"Unsafe path: {name}")
    if name == ".git" or name.startswith(".git/"):
        raise ValueError(f"Unsafe Git metadata: {name}")
    leaf = p.name.lower()
    if leaf == "local.properties" or leaf == ".env" or leaf.startswith(".env.") or leaf.endswith((".jks", ".keystore")):
        raise ValueError(f"Refusing to package credentials: {name}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()
    base = git("rev-parse", "--verify", args.base + "^{commit}").decode().strip()
    head = git("rev-parse", "--verify", args.head + "^{commit}").decode().strip()
    current = git("rev-parse", "HEAD").decode().strip()
    if current != head:
        raise RuntimeError("Checkout is not at requested head; refusing to pack unverified local contents")
    diff = git("diff", "--name-status", "--no-renames", "-z", base, head)
    pieces = diff.split(b"\0")
    if pieces[-1] != b"":
        raise RuntimeError("Unexpected git diff format")
    pieces.pop()
    if len(pieces) % 2:
        raise RuntimeError("Invalid git diff entries")
    changes = []
    for i in range(0, len(pieces), 2):
        action = pieces[i].decode("ascii")
        name = pieces[i + 1].decode("utf-8")
        check_name(name)
        if action not in ("A", "M", "D", "T"):
            raise RuntimeError(f"Unsupported action {action}: {name}")
        before = None if action == "A" else sha256_at(base, name)
        if action == "D":
            changes.append({"path": name, "operation": "delete", "before_sha256": before, "after_sha256": None})
            continue
        f = Path(name)
        if not f.is_file() or f.is_symlink():
            raise RuntimeError(f"Non-regular changed file: {name}")
        if f.stat().st_size > 200 * 1024 * 1024:
            raise RuntimeError(f"File exceeds 200 MiB; separate delivery required: {name}")
        if f.open("rb").read(128).startswith(b"version https://git-lfs.github.com/spec/v1"):
            raise RuntimeError(f"Git LFS pointer, not actual binary: {name}")
        changes.append({"path": name, "operation": "add" if action == "A" else "replace",
                        "before_sha256": before, "after_sha256": sha256_file(f), "size": f.stat().st_size})

    target = Path(args.output)
    script = Path(".github/scripts/apply_delta.ps1")
    manifest = {"format_version": 1, "project": "InGe+ Android", "base_commit": base, "head_commit": head,
                "created_utc": datetime.now(timezone.utc).isoformat(), "changes": changes}
    howto = (
        "InGe+ DELTA ZIP (not the complete GitHub repository)\n"
        f"BASE={base}\nHEAD={head}\n\n"
        "1. Extract ZIP to a temporary directory.\n"
        "2. First check (no changes):\n"
        "   powershell -ExecutionPolicy Bypass -File .\\apply_delta.ps1 -ProjectPath 'C:\\Users\\PC-02\\Documents\\InGePlus\\AppCalicatasDemo' -CheckOnly\n"
        "3. Only if preflight passes, apply:\n"
        "   powershell -ExecutionPolicy Bypass -File .\\apply_delta.ps1 -ProjectPath 'C:\\Users\\PC-02\\Documents\\InGePlus\\AppCalicatasDemo'\n"
        "Divergent local edits block the update. A backup is made beside the project.\n"
        "Deleted files are recorded in manifest.json and removed only after preflight.\n"
        "Download this DELTA asset, not GitHub's automatic Source code (zip).\n"
    )
    with ZipFile(target, "w", compression=ZIP_DEFLATED, compresslevel=6) as archive:
        archive.writestr("manifest.json", json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        archive.write(script, "apply_delta.ps1")
        archive.writestr("INSTRUCCIONES.txt", howto)
        # Additional optimization reports at ZIP root for immediate review.
        # Other release pipelines may not have them; keep tool generic.
        for report_name in ("CHANGELOG_COMPLETO.md", "REPORTE_PRUEBAS.md",
                            "CONFLICTOS_CESIUM.md", "ESTADO_HALLAZGOS.md"):
            report = Path("docs/optimization") / report_name
            if report.is_file():
                archive.write(report, report_name)
        for c in changes:
            if c["operation"] != "delete":
                archive.write(c["path"], "files/" + c["path"])
    additions = sum(c["operation"] == "add" for c in changes)
    replacements = sum(c["operation"] == "replace" for c in changes)
    deletions = sum(c["operation"] == "delete" for c in changes)
    target.with_suffix(".md").write_text(
        f"**InGe+ DELTA**: download the asset {target.name}, NOT Source code (zip).\n\n"
        f"Base: {base}\n\nHead: {head}\n\n"
        f"Files: {additions} added, {replacements} modified, {deletions} deleted.\n\n"
        "Extract and run apply_delta.ps1 with -CheckOnly before applying; divergent local files are never overwritten.\n",
        encoding="utf-8")
    print(f"Created {target}: {target.stat().st_size} bytes, {len(changes)} changed paths")


if __name__ == "__main__":
    main()
