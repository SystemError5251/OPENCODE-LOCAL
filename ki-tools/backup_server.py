#!/usr/bin/env python3
"""MCP server "ocl_backup": versioned tar.gz snapshots of the project, stored outside it.
Restores always go into a new folder; existing files are never overwritten."""

import hashlib
import json
import os
import sys
import tarfile
import time
from pathlib import Path, PurePosixPath

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ocl_mcp import Server, ToolError, human, inside, project_root, rel, state_dir  # noqa: E402

DEFAULT_EXCLUDE = [".trash", "node_modules", ".venv", "__pycache__", "*.gguf", "restored-*"]
server = Server("ocl_backup", instructions="Create a backup before risky changes. Backups are stored outside the project.")


def store():
    root = project_root()
    key = hashlib.sha256(str(root).encode()).hexdigest()[:8]
    return state_dir("backups", f"{root.name}-{key}")


def excluded(relpath, patterns):
    parts = PurePosixPath(relpath).parts
    return any(PurePosixPath(part).match(pat) for part in parts for pat in patterns)


def walk(patterns):
    root = project_root()
    for dirpath, dirnames, filenames in os.walk(root):
        d = Path(dirpath)
        dirnames[:] = [n for n in dirnames if not excluded((d / n).relative_to(root).as_posix(), patterns)]
        for n in filenames:
            f = d / n
            r = f.relative_to(root).as_posix()
            if not excluded(r, patterns) and (f.is_file() or f.is_symlink()):
                yield f, r


def file_hash(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load(id):
    if not id or "/" in id or id.startswith("."):
        raise ToolError("invalid backup id")
    meta = store() / f"{id}.json"
    if not meta.is_file():
        raise ToolError(f"no backup {id} (see list)")
    return json.loads(meta.read_text()), store() / f"{id}.tar.gz"


@server.tool(
    "Snapshot the whole project into a compressed backup outside the project.",
    {
        "note": {"type": "string", "description": "short description, e.g. 'before refactor'"},
        "exclude": {"type": "array", "items": {"type": "string"}, "description": "extra name patterns to skip"},
    },
)
def create(note="", exclude=None):
    patterns = DEFAULT_EXCLUDE + list(exclude or [])
    id = time.strftime("%Y%m%d-%H%M%S")
    archive = store() / f"{id}.tar.gz"
    if archive.exists():
        raise ToolError("a backup was created this second already, try again")
    hashes = {}
    with tarfile.open(archive, "w:gz") as tar:
        for f, r in walk(patterns):
            tar.add(f, arcname=r, recursive=False)
            if f.is_file() and not f.is_symlink():
                hashes[r] = file_hash(f)
    os.chmod(archive, 0o600)
    meta = {"id": id, "note": note, "project": str(project_root()), "files": hashes, "exclude": patterns}
    (store() / f"{id}.json").write_text(json.dumps(meta))
    return f"backup {id}: {len(hashes)} files, {human(archive.stat().st_size)}"


@server.tool("List the backups of this project, newest first.", name="list")
def list_backups():
    out = []
    for meta in sorted(store().glob("*.json"), reverse=True):
        m = json.loads(meta.read_text())
        archive = meta.with_suffix("").with_suffix(".tar.gz")
        size = human(archive.stat().st_size) if archive.exists() else "missing"
        out.append({"id": m["id"], "note": m.get("note", ""), "files": len(m["files"]), "size": size})
    return out or "no backups yet"


@server.tool(
    "Compare a backup with the current project: added, changed and removed files.",
    {"id": {"type": "string"}},
    ["id"],
)
def diff(id):
    m, _ = load(id)
    old = m["files"]
    now = {r: file_hash(f) for f, r in walk(m.get("exclude", DEFAULT_EXCLUDE)) if f.is_file() and not f.is_symlink()}
    return {
        "added": sorted(set(now) - set(old)),
        "removed": sorted(set(old) - set(now)),
        "changed": sorted(r for r in set(old) & set(now) if old[r] != now[r]),
    }


@server.tool(
    "Extract a backup into a NEW folder inside the project (default: restored-<id>). "
    "Optionally only one file or directory. Never overwrites anything.",
    {
        "id": {"type": "string"},
        "only": {"type": "string", "description": "path inside the backup to restore, default: everything"},
        "target": {"type": "string", "description": "new folder name, default restored-<id>"},
    },
    ["id"],
)
def restore(id, only="", target=""):
    _, archive = load(id)
    dest = inside(target or f"restored-{id}", must_exist=False)
    if dest.exists():
        raise ToolError(f"{rel(dest)} already exists")
    with tarfile.open(archive, "r:gz") as tar:
        members = []
        for m in tar.getmembers():
            name = PurePosixPath(m.name)
            if name.is_absolute() or ".." in name.parts or not (m.isfile() or m.isdir()):
                continue  # skip anything unsafe, including symlinks
            if only and not (m.name == only or m.name.startswith(only.rstrip("/") + "/")):
                continue
            members.append(m)
        if not members:
            raise ToolError("nothing to restore" + (f" matching {only}" if only else ""))
        dest.mkdir(parents=True)
        tar.extractall(dest, members=members, **({"filter": "data"} if hasattr(tarfile, "data_filter") else {}))
    return f"restored {len(members)} entries into {rel(dest)}"


if __name__ == "__main__":
    server.run()
